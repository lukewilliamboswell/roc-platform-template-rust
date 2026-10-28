#!/usr/bin/env roc-stable
app [main!] {
	ansi: "https://github.com/lukewilliamboswell/roc-ansi/releases/download/0.13.0/JXLM47L6CzrLXB5HBfqc27VnU6CD4jMm5Mk6dgbbovL.tar.zst",
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	roc: "nightly-2026-10-25-72704da",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst",
}

## Run, package and test the examples described by tests/spec.json.
##
## The spec uses the roc-automation shared nightly suite format, so the
## examples archive attached to each release is executable by the shared
## runner unchanged. Operations:
##
##   run      check, build and run every test_case in a suite with `roc` on PATH
##   package  freeze the examples into <name>-examples-<version>.zip
##   test     run a suite (working tree or --archive) against --bundle served
##            from loopback, with an empty package cache

import cli.Duration
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stderr
import weaver.Cli
import weaver.Opt
import src/BundleServer
import src/RocSource
import src/Script
import src/WeaverCli

name = "roc-platform-template-rust"

Case : { name : Str, args : List(Str), stdin : Str, stdout : Str, stderr : Str, exit_code : I32 }

App : { path : Str, cases : List(Case) }

Spec : { schema_version : U64, release : Str, dependencies : List(Str), apps : List(App) }

main! = |args| {
	options = match WeaverCli.parse!(cli_parser, args)? {
		Run(value) => value
		Exit => return Ok({})
	}
	match options.operation {
		"run" => run_suite!(Path.utf8(options.suite))
		"package" => package!(options.release_version, options.platform_url, Path.utf8(options.output))
		"test" => test!(Path.utf8(options.suite), options.archive, Path.utf8(options.bundle))
		_ => Err(UnknownOperation(options.operation))
	}
}

read_spec! : Path => Try(Spec, _)
read_spec! = |suite| {
	spec_path = if (Path.is_file!(Path.join(suite, "spec.json"))?) Path.join(suite, "spec.json") else Path.join(suite, "tests/spec.json")
	spec : Spec
	spec = Json.parse(Path.read_utf8!(spec_path)?)?
	Script.require!(spec.schema_version == 1 and !spec.apps.is_empty(), "${Path.display(spec_path)} is not a version 1 suite")?
	Ok(spec)
}

## Check and build each app once (with --opt=dev, as the shared runner does),
## then compare every case exactly. A compiler
## warning (exit 2) fails, as it does in the shared nightly runner.
run_suite! = |suite| {
	spec = read_spec!(suite)?
	roc = Script.roc!()?
	build_dir = Path.join(suite, ".examples-build")
	Path.create_all!(build_dir)?
	var $failures = []
	var $tested = 0.U64
	for example in spec.apps {
		source = Path.join(suite, example.path)
		exe = Path.join(build_dir, example.path.replace_each("/", "_").replace_last(".roc", ""))
		check = Script.exit_code!(roc.cmd(["check", Path.to_os_str(source)]))?
		build = Script.exit_code!(roc.cmd(["build", OsStr.from_str("--opt=dev"), Path.to_os_str(source), OsStr.from_str("--output=${Path.display(exe)}")]))?
		if check != 0 or build != 0 {
			$failures = $failures.append("${example.path}: roc check exited ${check.to_str()}, roc build exited ${build.to_str()}")
		} else {
			for test_case in example.cases {
				$tested = $tested + 1
				Script.info!("CASE", "${$tested.to_str()}: ${example.path} [${test_case.name}]")?
				output = Script.command(Path.to_os_str(exe)).base.args(test_case.args.map(OsStr.from_str)).stdin(Bytes(test_case.stdin.to_utf8())).timeout(Duration.seconds(10)).output_limit(MaxBytes(10_000_000)).manage_tree(Bool.True).run!().map_err(|err| CaseRunFailed(example.path, err))?
				code = match output.status {
					Exited(value) => value
					Signaled(_) => -1
				}
				stdout = Str.from_utf8_lossy(output.stdout_bytes)
				stderr = Str.from_utf8_lossy(output.stderr_bytes)
				if stdout == test_case.stdout and stderr == test_case.stderr and code == test_case.exit_code {
					Script.pass!("${example.path} [${test_case.name}]")?
				} else {
					Stderr.line!("expected stdout ${Json.to_str(test_case.stdout)}\n  actual ${Json.to_str(stdout)}\nexpected stderr ${Json.to_str(test_case.stderr)}\n  actual ${Json.to_str(stderr)}\nexpected exit ${test_case.exit_code.to_str()}, actual ${code.to_str()}")?
					$failures = $failures.append("${example.path} [${test_case.name}]")
				}
			}
		}
	}
	Script.info!("SUMMARY", "${$tested.to_str()} cases executed; ${$failures.len().to_str()} failures; 0 skipped")?
	if $failures.is_empty() {
		Script.pass!("All example cases passed.")
	} else {
		Script.fail!("Failing example cases:\n  ${Str.join_with($failures, "\n  ")}")
	}
}

## Freeze the examples: each app names the release bundle and nothing else
## changes. The archive root is named after the archive.
package! = |version, platform_url, output| {
	Script.require!(!version.is_empty() and Script.ends_with(platform_url, ".tar.zst"), "package needs --release-version and a .tar.zst --platform-url")?
	root_name = "${name}-examples-${version}"
	Script.require!(Path.display(output).ends_with("/${root_name}.zip") or Path.display(output) == "${root_name}.zip", "output must be named ${root_name}.zip")?
	spec = read_spec!(Path.utf8("."))?
	Script.require!(spec.release == "working-tree" and spec.dependencies.is_empty(), "tests/spec.json must describe the working tree")?
	output_absolute = Path.absolute!(output)?
	Env.with_temp_dir!(
		|temp| {
			root = Path.join(temp, root_name)
			Path.create_all!(root)?
			for example in spec.apps {
				destination = Path.join(root, example.path)
				directory = match Str.split_on(example.path, "/") {
					[.. as parents, _] => Str.join_with(parents, "/")
					[] => ""
				}
				Path.create_all!(Path.join(root, directory))?
				frozen = RocSource.replace_platform(Path.read_utf8!(Path.utf8(example.path))?, platform_url)?
				Path.write_utf8!(destination, frozen)?
			}
			Path.write_utf8!(Path.join(root, "spec.json"), Json.to_str({ schema_version: spec.schema_version, release: version, dependencies: [platform_url], apps: spec.apps }))?
			Path.write_utf8!(Path.join(root, "README.md"), readme(version, platform_url))?
			Script.command("zip").base.args(["-X", "-q", "-r", Path.display(output_absolute), root_name].map(OsStr.from_str)).cwd(temp).call!()?
			Script.pass!("Created: ${Path.display(output)}")
		},
	)
}

readme = |version, url|
	"# ${name} ${version} examples\n\nThese examples use the ${version} platform bundle:\n\n${url}\n\nRun one with `roc examples/hello_world/main.roc`. `spec.json` records the\narguments, input and exact output of each example.\n"

## Copy the suite, point every app at the loopback bundle, and run it in a
## child with a fresh package cache while this process serves the bundle.
test! = |suite, archive, bundle| {
	Script.require!(Script.ends_with(Path.display(bundle), ".tar.zst") and Path.is_file!(bundle)?, "test needs an existing --bundle .tar.zst")?
	filename = Path.filename(bundle).map_ok(Path.display).map_err(|_| InvalidBundlePath(Path.display(bundle)))?
	bundle_bytes = Path.read_bytes!(bundle)?
	script = Path.absolute!(Path.utf8("scripts/examples.roc"))?
	Env.with_temp_dir!(
		|temp| {
			staged = Path.join(temp, "suite")
			if archive.is_empty() {
				Path.create_all!(staged)?
				Path.copy_dir!(Path.join(suite, "examples"), Path.join(staged, "examples"))?
				Path.copy_dir!(Path.join(suite, "tests"), Path.join(staged, "tests"))?
			} else {
				Script.command("unzip").base.args(["-q", archive, "-d", Path.display(temp)].map(OsStr.from_str)).call!()?
				root = Path.utf8(Path.display(temp).concat("/").concat(Path.filename(Path.utf8(archive)).map_ok(Path.display)?.replace_last(".zip", "")))
				Path.rename!(root, staged)?
				spec = read_spec!(staged)?
				Script.require!(spec.dependencies.any(|url| Script.ends_with(url, "/${filename}")), "the archive does not name ${filename}")?
			}
			BundleServer.with!(
				filename,
				bundle_bytes,
				|server| {
					for example in read_spec!(staged)?.apps {
						path = Path.join(staged, example.path)
						Path.write_utf8!(path, RocSource.replace_platform(Path.read_utf8!(path)?, server.url())?)?
					}
					child = Script.roc_stable!()?.cmd([Path.to_os_str(script), OsStr.from_str("--"), OsStr.from_str("--operation"), OsStr.from_str("run"), OsStr.from_str("--suite"), Path.to_os_str(staged)])
						.envs([(OsStr.from_str("ROC_CACHE_DIR"), Path.to_os_str(Path.join(temp, "cache")))])
						.stdout(Capture)
						.stderr(Capture)
						.spawn!()
						.map_err(|err| SuiteSpawnFailed(err))?
					output = server.serve_child!(child)?
					Stderr.write_bytes!(output.stdout_bytes)?
					Stderr.write_bytes!(output.stderr_bytes)?
					match output.status {
						Exited(0) => Script.pass!("Examples passed against ${filename}")
						Exited(code) => Err(SuiteExited(code))
						Signaled(signal) => Err(SuiteSignaled(signal))
					}
				},
			)
		},
	)
}

cli_parser = Cli.assert_valid(
	Cli.finish(
		{
			operation: Opt.str({ short: "", long: "operation", help: "run, package, or test.", default: Value("run") }),
			suite: Opt.str({ short: "", long: "suite", help: "Suite root holding spec.json or tests/spec.json.", default: Value(".") }),
			release_version: Opt.str({ short: "", long: "release-version", help: "Release version for package.", default: Value("") }),
			platform_url: Opt.str({ short: "", long: "platform-url", help: "Released bundle URL for package.", default: Value("") }),
			output: Opt.str({ short: "", long: "output", help: "Archive to create with package.", default: Value("") }),
			archive: Opt.str({ short: "", long: "archive", help: "Examples archive to test instead of the working tree.", default: Value("") }),
			bundle: Opt.str({ short: "", long: "bundle", help: "Platform bundle to serve for test.", default: Value("") }),
		}.Cli,
		{ name: "examples", version: "development", authors: [], description: "Run, package and test the platform examples.", text_style: Plain },
	),
)
