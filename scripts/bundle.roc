#!/usr/bin/env roc-stable
app [main!] {
	ansi: "https://github.com/lukewilliamboswell/roc-ansi/releases/download/0.13.0/JXLM47L6CzrLXB5HBfqc27VnU6CD4jMm5Mk6dgbbovL.tar.zst",
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	roc: "nightly-2026-10-25-72704da",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst",
}

## Bundle the platform into <output-dir>/<content-hash>.tar.zst.
##
## `--target all` (the release default) refuses a partial bundle: every target's
## host and linker inputs and the linker-input provenance metadata must exist.
## `--target native` bundles a header naming only this machine's target, for
## testing a bundle without cross-compiling.

import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout
import weaver.Cli
import weaver.Opt
import src/Files
import src/Script
import src/Targets
import src/WeaverCli

main! = |args| {
	options = match WeaverCli.parse!(cli_parser, args)? {
		Run(value) => value
		Exit => return Ok({})
	}
	Script.require!(!options.output_dir.is_empty(), "bundle needs --output-dir")?
	selected = match options.target {
		"all" => Targets.all
		"native" => [Targets.native!()?]
		other => return Err(UnknownTarget(other))
	}
	source_dir = Path.utf8("platform")
	for target in selected {
		Targets.require_files!(source_dir, target)?
	}
	Script.require!(options.target == "native" or Path.is_file!(Path.utf8("platform/runtime/manifest.json"))?, "Missing linker-input provenance metadata; run blueprint run build-platform -- --target all")?
	output_dir = Path.absolute!(Path.utf8(options.output_dir))?
	Path.create_all!(output_dir)?
	Env.with_temp_dir!(
		|stage| {
			copy_platform!(source_dir, stage, selected)?
			if options.target == "native" {
				main_path = Path.join(stage, "main.roc")
				Path.write_utf8!(main_path, only_targets(Path.read_utf8!(main_path)?, selected))?
			}
			members = bundle_members!(stage, selected)?
			bundle = create_bundle!(stage, members, output_dir)?
			Stdout.line!("Created: ${Path.display(bundle)}")
		},
	)
}

copy_platform! = |source_dir, stage, selected| {
	for path in Files.direct_files!(source_dir)? {
		if Path.ext(path).map_ok(Path.display) == Ok("roc") {
			Path.copy!(path, Path.join(stage, Path.filename(path).map_ok(Path.display)?))?
		}
	}
	if Path.is_dir!(Path.join(source_dir, "runtime"))? {
		Path.copy_dir!(Path.join(source_dir, "runtime"), Path.join(stage, "runtime"))?
	}
	for target in selected {
		directory = Path.join(stage, "targets/${target}")
		Path.create_all!(directory)?
		for file in Targets.files(target) {
			Path.copy!(Path.join(source_dir, "targets/${target}/${file}"), Path.join(directory, file))?
		}
	}
	Ok({})
}

## Replace the header's `targets` block with entries for the selected targets.
only_targets = |source, selected| {
	var $lines = []
	var $skipping = Bool.False
	for line in Str.split_on(source, "\n") {
		trimmed = line.trim()
		if !$skipping and trimmed == "targets: {" {
			$lines = $lines.append("\ttargets: {").append("\t\tinputs_dir: \"targets/\",")
			for target in selected {
				$lines = $lines.append("\t\t${target}: { inputs: ${Targets.inputs(target)} },")
			}
			$lines = $lines.append("\t}")
			$skipping = Bool.True
		} else if $skipping {
			if trimmed == "}" {
				$skipping = Bool.False
			}
		} else {
			$lines = $lines.append(line)
		}
	}
	Str.join_with($lines, "\n")
}

bundle_members! = |stage, selected| {
	var $members = []
	for path in Files.direct_files!(stage)? {
		$members = $members.append(Path.filename(path).map_ok(Path.display)?)
	}
	for target in selected {
		for file in Targets.files(target) {
			$members = $members.append("targets/${target}/${file}")
		}
	}
	runtime = Path.join(stage, "runtime")
	if Path.is_dir!(runtime)? {
		prefix = Path.display(stage).concat("/")
		for path in Files.files!(runtime)? {
			$members = $members.append(Path.display(path).replace_first(prefix, ""))
		}
	}
	Ok($members)
}

## `roc bundle` reports the archive relative to its working directory, so
## locate it by name in the output directory instead.
create_bundle! = |stage, members, output_dir| {
	roc = Script.roc!()?
	output = roc.base.args(["bundle"].concat(members).concat(["--output-dir", Path.display(output_dir)]).map(OsStr.from_str)).cwd(stage).run!().map_err(|err| BundleFailed(err))?
	stdout = Str.from_utf8_lossy(output.stdout_bytes)
	Stdout.write!(stdout)?
	match output.status {
		Exited(0) => {}
		Exited(code) => return Err(BundleExited(code, Str.from_utf8_lossy(output.stderr_bytes)))
		Signaled(signal) => return Err(BundleSignaled(signal))
	}
	created = Str.split_on(stdout, "\n").keep_if(|line| Script.starts_with(line, "Created: "))
	match created {
		[line] => {
			filename = match Str.split_on(line.trim(), "/") {
				[.., last] => last.replace_first("Created: ", "")
				[] => ""
			}
			Ok(Path.join(output_dir, filename))
		}
		_ => Err(BundlePathNotReported)
	}
}

cli_parser = Cli.assert_valid(
	Cli.finish(
		{
			output_dir: Opt.str({ short: "", long: "output-dir", help: "Directory for the .tar.zst bundle.", default: Value("") }),
			target: Opt.str({ short: "", long: "target", help: "all (default) or native.", default: Value("all") }),
		}.Cli,
		{ name: "bundle", version: "development", authors: [], description: "Bundle the platform.", text_style: Plain },
	),
)
