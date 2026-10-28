import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stderr
import cli.Stdout
import ansi.ANSI

## Shared command, environment, error, and terminal-output helpers.
Script := [].{
	Command := { base : Cmd.Command, program : OsStr }.{
		run! = |self, args| {
			command = self.base.args(args)
			display = Str.join_with([self.program].concat(args).map(OsStr.display), " ")
			Stdout.line!("\n${heading("RUN", Cyan)} ${display}")?
			command.call!()
		}

		capture! = |self, args, cwd, stdin|
			run_capture!(self.base, args, cwd, stdin)

		## Run to completion with both streams captured, whatever the exit
		## status, for a caller that reports the output only on failure.
		output! = |self, args, cwd|
			self.base.args(args).cwd(cwd).run!().map_err(|err| CommandRunFailed(err))

		spawn! = |self, args, cwd|
			self.base.args(args).cwd(cwd).stdout(Capture).stderr(Capture).spawn!().map_err(|err| CommandSpawnFailed(err))

		cmd = |self, args| self.base.args(args)
	}

	command = |program| Command.{ base: Cmd.new(program), program }

	## A command that sees only the named environment variables, each with the
	## value this process has. A compiler run this way cannot pick anything up
	## from the surroundings it happens to be started in.
	sealed_command! = |program, names| {
		var $kept = []
		for name in names {
			match Env.var!(name) {
				Ok(value) => {
					$kept = $kept.append((name, value))
				}
				Err(VarNotFound(_)) => {}
				Err(err) => return Err(EnvironmentInputError(OsStr.display(name), err))
			}
		}
		Ok(Command.{ base: Cmd.new(program).clear_envs().envs($kept), program })
	}

	## The tooling compiler that Blueprint.roc names. It runs the scripts and
	## nothing else.
	roc_stable! = || Ok(command("roc-stable"))

	## The package compiler: whatever `roc` is on PATH, which is meant to be the
	## latest nightly. It checks, tests, bundles and builds the platform and
	## every application that depends on it.
	roc! = || Ok(command("roc"))

	env_str! = |name|
		Env.var_str!(name).map_err(|err| EnvironmentInputError(OsStr.display(name), err))

	env_str_or! = |name, fallback|
		match Env.var_str!(name) {
			Ok(value) => Ok(value)
			Err(VarNotFound(_)) => Ok(fallback)
			Err(err) => Err(EnvironmentInputError(OsStr.display(name), err))
		}

	env_path! = |name|
		match Script.env_str!(name) {
			Ok(value) => Ok(Path.utf8(value))
			Err(err) => Err(err)
		}
	env_path_or! = |name, fallback|
		match Script.env_str_or!(name, Path.display(fallback)) {
			Ok(value) => Ok(Path.utf8(value))
			Err(err) => Err(err)
		}

	pass! = |message| Stdout.line!("${heading("PASS", Green)} ${message}")
	info! = |label, message| Stdout.line!("${heading(label, Cyan)} ${message}")
	warn! = |message| Stdout.line!("${heading("WARN", Yellow)} ${message}")

	fail! = |message| {
		Stderr.line!("error: ${message}")?
		Err(ScriptFailed)
	}

	require! = |condition, message| if (condition) Ok({}) else fail!(message)

	require_file! = |path|
		if (Path.is_file!(path)?) Ok({}) else Script.fail!("file does not exist: ${Path.display(path)}")

	run_capture! = |base, args, cwd, stdin| {
		output = base.args(args).cwd(cwd).stdin(Bytes(stdin)).run!().map_err(|err| CommandRunFailed(err))?
		command_output!(output)
	}

	wait_capture! = |child| {
		output = child.wait!().map_err(|err| CommandWaitFailed(err))?
		command_output!(output)
	}

	## Run with the terminal inherited and return the exit code for the caller
	## to judge. Ending on a signal is still a failure.
	exit_code! = |cmd|
		match cmd.inherit_stdio().run!()?.status {
			Exited(code) => Ok(code)
			Signaled(signal) => Err(CommandSignaled(signal))
		}

	starts_with = |value, prefix| value.to_utf8().take_first(prefix.to_utf8().len()) == prefix.to_utf8()
	ends_with = |value, suffix| {
		bytes = value.to_utf8()
		tail = suffix.to_utf8()
		bytes.len() >= tail.len() and bytes.drop_first(bytes.len() - tail.len()) == tail
	}

	trim = |value| Str.from_utf8_lossy(trim_bytes(value.to_utf8()))
}

command_output! = |output|
	match output.status {
		Exited(0) => Ok(output.stdout_bytes)
		Exited(code) => {
			Stderr.write_bytes!(output.stderr_bytes)?
			Err(CommandExited(code))
		}
		Signaled(signal) => {
			Stderr.write_bytes!(output.stderr_bytes)?
			Err(CommandSignaled(signal))
		}
	}

trim_bytes = |bytes|
	match bytes {
		[first, .. as rest] if first == 32 or first == 9 or first == 10 or first == 13 => trim_bytes(rest)
		_ => trim_end(bytes)
	}

trim_end = |bytes|
	match bytes {
		[.. as rest, last] if last == 32 or last == 9 or last == 10 or last == 13 => trim_end(rest)
		_ => bytes
	}

heading = |label, color| ANSI.color(label, { fg: Standard(color), bg: Default })
