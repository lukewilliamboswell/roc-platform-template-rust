import cli.Cmd
import cli.Duration
import cli.Env
import cli.OsStr
import cli.Path

## Content-locked linker-input admission and routine installation.
Runtime := [].{
	repository = "lukewilliamboswell/roc-platform-template-rust"
	workflow = ".github/workflows/runtime-release.yml"
	target_names = ["x64musl", "arm64musl"]
	libraries = ["crt1.o", "libc.a", "libunwind.a", "libzigc.a", "libcompiler_rt.a"]
	license_files = ["licenses/musl.txt", "licenses/libunwind.txt", "licenses/zig.txt"]
	producer_inputs = ["scripts/runtime_build.roc", "scripts/runtime.roc", "scripts/runtime_test.roc", "scripts/src/Runtime.roc", "scripts/src/RuntimeProducer.roc", "runtime/source.json", "runtime/smoke.c", "runtime/test-toolchains.json", ".github/workflows/runtime-release.yml", "Blueprint.roc", "Blueprint.lock"]

	Member : { name : Str, bytes : List(U8) }
	FileHash : { name : Str, sha256 : Str }
	Source : { zig_version : Str, url : Str, sha256 : Str, source_url : Str, source_sha256 : Str }
	TargetRecord : { asset : Str, sha256 : Str, size : U64 }
	Lock : { schema_version : U64, kind : Str, repository : Str, release : Str, manifest : { asset : Str, sha256 : Str }, source : { repository : Str, sha : Str, ref : Str, workflow : Str, input_fingerprint : Str }, target_records : { x64musl : TargetRecord, arm64musl : TargetRecord } }

	target_triple = |target| match target {
		"x64musl" => Ok("x86_64-linux-musl")
		"arm64musl" => Ok("aarch64-linux-musl")
		_ => Err(UnknownTarget(target))
	}

	require! = |condition, reason| if (condition) Ok({}) else Err(InvalidRuntime(reason))

	run! = |argv| {
		output = command!(argv, [])?
		require!(output.status == Exited(0), "Command failed: ${Str.join_with(argv, " ")}\n${Str.from_utf8_lossy(output.stderr_bytes)}")?
		Ok(Str.from_utf8_lossy(output.stdout_bytes))
	}

	command! = |argv, stdin| match argv {
		[program, .. as arguments] => Cmd.new(OsStr.from_str(program)).args(arguments.map(OsStr.from_str)).stdin(Bytes(stdin)).timeout(Duration.seconds(600)).manage_tree(Bool.True).output_limit(MaxBytes(100_000_000)).run!()
		[] => Err(EmptyRuntimeCommand)
	}

	sha! = |path| {
		output = run!(["sha256sum", Path.display(path)])?
		match Str.split_on(output, " ") {
			[value, ..] if hex(value, 64) => Ok(value)
			_ => Err(InvalidHashOutput)
		}
	}

	bytes_sha! = |bytes| {
		output = command!(["sha256sum"], bytes)?
		require!(output.status == Exited(0), "Cannot hash runtime bytes")?
		match Str.split_on(Str.from_utf8_lossy(output.stdout_bytes), " ") {
			[value, ..] if hex(value, 64) => Ok(value)
			_ => Err(InvalidHashOutput)
		}
	}

	valid_ref = |value| value.starts_with("refs/heads/") and !value.drop_prefix("refs/heads/").is_empty() and !value.contains("..") and value.to_utf8().all(|byte| (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or (byte >= '0' and byte <= '9') or ['.', '_', '/', '-'].contains(byte))

	hex = |value, len| value.to_utf8().len() == len and value.to_utf8().all(|byte| (byte >= '0' and byte <= '9') or (byte >= 'a' and byte <= 'f'))

	fingerprint! = || {
		for name in producer_inputs {
			require!(Path.is_file!(Path.utf8(name))? and !Path.is_sym_link!(Path.utf8(name))?, "Producer input must be a regular file: ${name}")?
		}
		clean = command!(["git", "diff", "--quiet", "HEAD", "--"].concat(producer_inputs), [])?
		require!(clean.status == Exited(0), "Uncommitted linker-input producer changes; commit and run the trusted publisher")?
		var $lines = ""
		for name in producer_inputs {
			blob = run!(["git", "rev-parse", "HEAD:${name}"])?.trim()
			require!(hex(blob, 40), "Producer input is not committed: ${name}")?
			$lines = $lines.concat("${name}\u(0000)${blob}\n")
		}
		bytes_sha!($lines.to_utf8())
	}

	expected_members = |target| (if (target == "all") target_names else [target]).join_map(|item| libraries.map(|name| "targets/${item}/${name}")).concat(license_files).append("manifest.json")

	## Read one fixed inventory, never extract an archive into a directory. All
	## headers and all inner hashes are checked before installation can begin.
	inspect! = |archive, target| {
		if target != "all" {
			_ = target_triple(target)?
		}
		listing = run!(["tar", "-tf", Path.display(archive)])?
		names = Str.split_on(listing, "\n").keep_if(|name| !name.is_empty())
		expected = expected_members(target)
		require!(valid_members(names, expected), "Unexpected, duplicate or missing linker-input archive member")?
		verbose = run!(["tar", "-tvf", Path.display(archive)])?
		require!(Str.split_on(verbose, "\n").keep_if(|line| !line.is_empty()).all(|line| line.starts_with("-")), "Linker-input archive contains a link or special file")?
		var $members = []
		for name in names {
			output = command!(["tar", "-xOf", Path.display(archive), "--", name], [])?
			require!(output.status == Exited(0) and output.stdout_bytes.len() <= 64 * 1024 * 1024, "Cannot read bounded linker-input member ${name}")?
			$members = $members.append({ name, bytes: output.stdout_bytes })
		}
		manifest = $members.keep_if(|member| member.name == "manifest.json").first()?
		valid = command!(["jq", "-e", ".schema_version == 1 and .targets == {x64musl: \"x86_64-linux-musl\", arm64musl: \"aarch64-linux-musl\"}"], manifest.bytes)?
		require!(valid.status == Exited(0), "Unsupported runtime manifest")?
		source_output = command!(["jq", "-c", ".source"], manifest.bytes)?
		actual_source : Source
		actual_source = Json.parse(Str.from_utf8_lossy(source_output.stdout_bytes))?
		declared_source : Source
		declared_source = Json.parse(Path.read_utf8!(Path.utf8("runtime/source.json"))?)?
		require!(actual_source == declared_source, "Runtime archive source differs from reviewed source pin")?
		files_output = command!(["jq", "-c", ".files | to_entries | map({name: .key, sha256: .value})"], manifest.bytes)?
		require!(files_output.status == Exited(0), "Invalid runtime manifest file inventory")?
		files : List(FileHash)
		files = Json.parse(Str.from_utf8_lossy(files_output.stdout_bytes))?
		all_files = target_names.join_map(|item| libraries.map(|name| "targets/${item}/${name}")).concat(license_files)
		require!(valid_members(files.map(|file| file.name), all_files), "Manifest file inventory differs from runtime contract")?
		for member in $members.keep_if(|member| member.name != "manifest.json") {
			entry = files.keep_if(|file| file.name == member.name).first()?
			require!(hex(entry.sha256, 64) and bytes_sha!(member.bytes)? == entry.sha256, "Runtime member SHA-256 differs from manifest: ${member.name}")?
		}
		Ok($members)
	}

	valid_members = |actual, expected| actual.len() == expected.len() and actual.all(|name| expected.contains(name)) and actual.all(|name| actual.keep_if(|other| name == other).len() == 1)

	install! = |archive, target| {
		members = inspect!(archive, target)?
		for member in members {
			safe_destination!(destination(member.name))?
		}
		for member in members {
			path = destination(member.name)
			parents = Str.split_on(Path.display(path), "/").drop_last(1)
			Path.create_all!(Path.utf8(Str.join_with(parents, "/")))?
			Path.write_bytes!(path, member.bytes)?
		}
		Ok({})
	}

	destination = |name| Path.utf8(if (name.starts_with("targets/")) "platform/${name}" else "platform/runtime/${name}")

	safe_destination! = |path| {
		var $cursor = ""
		for part in Str.split_on(Path.display(path), "/") {
			$cursor = if ($cursor.is_empty()) part else "${$cursor}/${part}"
			require!(!Path.is_sym_link!(Path.utf8($cursor))?, "Symlink in runtime destination ${$cursor}")?
		}
		Ok({})
	}

	fetch! = |selected| {
		lock_file = Path.utf8("runtime/link-inputs.lock.json")
		raw = Path.read_utf8!(lock_file)?
		shape = command!(["jq", "-e", "(keys | sort) == ([\"schema_version\",\"kind\",\"repository\",\"release\",\"manifest\",\"source\",\"targets\"] | sort) and (.targets | keys | sort) == [\"arm64musl\",\"x64musl\"] and (.source | keys | sort) == [\"input_fingerprint\",\"ref\",\"repository\",\"sha\",\"workflow\"] and (.manifest | keys | sort) == [\"asset\",\"sha256\"] and (.targets | to_entries | all(.value | (keys | sort) == [\"asset\",\"sha256\",\"size\"]))"], raw.to_utf8())?
		require!(shape.status == Exited(0), "Unsupported linker-input lock fields")?
		renamed = command!(["jq", "-c", ".target_records = .targets | del(.targets)"], raw.to_utf8())?
		lock : Lock
		lock = Json.parse(Str.from_utf8_lossy(renamed.stdout_bytes))?
		require!(lock.schema_version == 1 and lock.kind == "link-inputs" and lock.repository == repository and lock.release == "linker-inputs-sha256-${lock.manifest.sha256}" and lock.manifest.asset == "build-input-release.json" and hex(lock.manifest.sha256, 64), "Unsupported linker-input lock identity")?
		require!(lock.source.repository == repository and lock.source.workflow == "${repository}/${workflow}" and hex(lock.source.sha, 40) and valid_ref(lock.source.ref), "Invalid linker-input producer identity")?
		require!(lock.source.input_fingerprint == fingerprint!()?, "Linker-input producer inputs changed; publish and adopt a new content lock")?
		home = Env.var_str!("HOME")?
		cache = Path.utf8(
			match Env.var_str!("ROC_LINK_INPUT_CACHE") {
				Ok(value) => value
				Err(_) => "${home}/.cache/roc-platform-template-rust/link-inputs"
			},
		)
		Path.create_all!(cache)?
		for target in selected {
			record = match target {
				"x64musl" => lock.target_records.x64musl
				"arm64musl" => lock.target_records.arm64musl
				_ => return Err(UnknownTarget(target))
			}
			require!(record.size > 0 and hex(record.sha256, 64) and record.asset == "link-inputs-${target}.tar", "Invalid target archive lock record")?
			archive = Path.join(cache, record.sha256)
			var $valid = Bool.False
			if Path.is_file!(archive)? {
				$valid = Path.read_bytes!(archive)?.len() == record.size and sha!(archive)? == record.sha256
			}
			if !$valid {
				if Path.is_file!(archive)? {
					Path.delete!(archive)?
				}
				require!(!Path.is_sym_link!(archive)?, "Symlink in linker-input cache")?
				_ = run!(["curl", "--fail", "--location", "--proto", "=https", "--max-time", "120", "--output", Path.display(archive), "https://github.com/${repository}/releases/download/${lock.release}/${record.asset}"])?
			}
			if Path.read_bytes!(archive)?.len() != record.size or sha!(archive)? != record.sha256 {
				Path.delete!(archive)?
				return Err(InvalidRuntime("Downloaded linker-input archive differs from lock"))
			}
			install!(archive, target)?
		}
		Ok({})
	}
}

expect Runtime.valid_members(["a", "b"], ["b", "a"])
expect !Runtime.valid_members(["a", "a"], ["a", "b"])
expect !Runtime.valid_members(["../a"], ["a"])
expect !Runtime.valid_members(["a", "b"], ["a"])
expect Runtime.hex("abc012", 6)
expect !Runtime.hex("ABC012", 6)

expect Runtime.valid_ref("refs/heads/feature/native-inputs")
expect !Runtime.valid_ref("refs/heads/")
expect !Runtime.valid_ref("refs/heads/main\n")
expect !Runtime.valid_ref("refs/heads/../main")
