#!/usr/bin/env roc-stable
app [main!] {
	ansi: "https://github.com/lukewilliamboswell/roc-ansi/releases/download/0.13.0/JXLM47L6CzrLXB5HBfqc27VnU6CD4jMm5Mk6dgbbovL.tar.zst",
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	roc: "nightly-2026-10-25-72704da",
}

## The aggregate pull-request check behind `blueprint run check`: tooling,
## platform, working-tree examples, and the examples against a native bundle.

import cli.Env
import cli.OsStr
import cli.Path
import src/Files
import src/Script

main! = |_args| {
	check_tooling!()?
	check_platform!()?
	run_script!("scripts/build_platform.roc", [])?
	run_script!("scripts/examples.roc", ["--operation", "run"])?
	check_bundle!()?
	check_worktree!()?
	Script.pass!("Repository checks completed successfully.")
}

check_tooling! = || {
	Script.info!("CHECK", "Formatting and type-checking repository tooling")?
	stable = Script.roc_stable!()?
	script_files = Files.roc_files!(Path.utf8("scripts"))?
	stable.run!(["fmt", "--check"].map(OsStr.from_str).concat(script_files.map(Path.to_os_str)))?
	for path in Files.direct_files!(Path.utf8("scripts"))? {
		if Path.ext(path).map_ok(Path.display) == Ok("roc") {
			stable.run!([OsStr.from_str("check"), Path.to_os_str(path)])?
		}
	}
	Ok({})
}

check_platform! = || {
	Script.info!("CHECK", "Formatting, type-checking and testing the platform with the latest nightly")?
	roc = Script.roc!()?
	roc.run!(["fmt", "--check", "platform", "examples"].map(OsStr.from_str))?
	roc.run!(["check", "platform/main.roc"].map(OsStr.from_str))?
	for path in Files.roc_files!(Path.utf8("examples"))? {
		if Path.read_utf8!(path)?.contains("\nexpect ") {
			roc.run!([OsStr.from_str("test"), Path.to_os_str(path)])?
		}
	}
	Ok({})
}

check_bundle! = || {
	Script.info!("CHECK", "Examples against a native bundle served from loopback")?
	Env.with_temp_dir!(
		|temp| {
			run_script!("scripts/bundle.roc", ["--target", "native", "--output-dir", Path.display(temp)])?
			bundles = Files.direct_files!(temp)?.keep_if(|path| Script.ends_with(Path.display(path), ".tar.zst"))
			match bundles {
				[bundle] => run_script!("scripts/examples.roc", ["--operation", "test", "--bundle", Path.display(bundle)])
				_ => Err(ExpectedOneBundle)
			}
		},
	)
}

check_worktree! = || {
	Script.info!("CHECK", "Looking for whitespace errors in the Git diff")?
	Script.command("git").run!(["diff", "--check"].map(OsStr.from_str))
}

run_script! = |script, args| Script.roc_stable!()?.run!([script, "--"].concat(args).map(OsStr.from_str))
