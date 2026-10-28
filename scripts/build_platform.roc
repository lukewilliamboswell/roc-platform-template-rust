#!/usr/bin/env roc-stable
app [main!] {
	ansi: "https://github.com/lukewilliamboswell/roc-ansi/releases/download/0.13.0/JXLM47L6CzrLXB5HBfqc27VnU6CD4jMm5Mk6dgbbovL.tar.zst",
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	roc: "nightly-2026-10-25-72704da",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst",
}

## Build the Rust host into platform/targets/<target>/libhost.a.
##
## The default builds the native target; `--target all` cross-compiles every
## supported target. Musl targets first install the verified linker inputs from
## their independent release (or an explicit `--runtime-candidate` archive).

import cli.OsStr
import cli.Path
import weaver.Cli
import weaver.Opt
import src/Script
import src/Targets
import src/WeaverCli

main! = |args| {
	options = match WeaverCli.parse!(cli_parser, args)? {
		Run(value) => value
		Exit => return Ok({})
	}
	native = Targets.native!()?
	selected = match options.target {
		"native" => [native]
		"all" => Targets.all
		other => if (Targets.all.contains(other)) [other] else return Err(UnknownTarget(other))
	}
	install_linker_inputs!(selected, options.runtime_candidate)?
	if options.skip_host {
		return Script.pass!("Verified linker inputs; reusing fingerprinted host archives")
	}
	for target in selected {
		build!(target, target == native)?
	}
	Script.pass!("Built ${Str.join_with(selected, ", ")}")
}

install_linker_inputs! = |selected, candidate| {
	musl = selected.keep_if(|target| Script.ends_with(target, "musl"))
	if musl.is_empty() {
		Ok({})
	} else if !candidate.is_empty() {
		run!("python3", ["ci/runtime.py", "install-candidate", candidate])
	} else {
		run!("python3", ["ci/runtime.py", "fetch"].concat(musl.join_map(|target| ["--target", target])))
	}
}

## A native macOS build needs no --target; Linux always targets musl, since the
## default host triple is glibc.
build! = |target, is_native| {
	triple = Targets.rust_triple(target)?
	Script.info!("BUILD", "${target} (${triple})")?
	if is_native and !Script.ends_with(target, "musl") {
		run!("cargo", ["build", "--release", "--locked", "--lib"])?
		copy_host!(target, "target/release/libhost.a")
	} else {
		run!("cargo", ["build", "--release", "--locked", "--lib", "--target", triple])?
		copy_host!(target, "target/${triple}/release/libhost.a")
	}
}

copy_host! = |target, built| {
	directory = Path.utf8("platform/targets/${target}")
	Path.create_all!(directory)?
	Path.copy!(Path.utf8(built), Path.join(directory, "libhost.a"))?
	Script.info!("HOST", "platform/targets/${target}/libhost.a")
}

run! = |program, args| Script.command(program).run!(args.map(OsStr.from_str))

cli_parser = Cli.assert_valid(
	Cli.finish(
		{
			skip_host: Opt.flag({ short: "", long: "skip-host", help: "Verify/install linker inputs without compiling cached hosts.", default: Bool.False }),
			target: Opt.str({ short: "", long: "target", help: "native (default), all, or one of x64mac, arm64mac, x64musl, arm64musl.", default: Value("native") }),
			runtime_candidate: Opt.str({ short: "", long: "runtime-candidate", help: "Unpublished linker-input archive to install instead of the release.", default: Value("") }),
		}.Cli,
		{ name: "build-platform", version: "development", authors: [], description: "Build the Rust host for the platform targets.", text_style: Plain },
	),
)
