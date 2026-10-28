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
		for target in selected {
			host = Path.utf8("platform/targets/${target}/libhost.a")
			recorded = Path.utf8("platform/targets/${target}/libhost.a.sha256")
			Script.require!(Path.type!(host)? == IsFile and Path.type!(recorded)? == IsFile, "Missing regular cached host or digest: ${target}")?
			actual = host_digest!(host)?
			Script.require!(actual == Path.read_utf8!(recorded)?, "Cached host digest mismatch: ${target}")?
		}
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
		run!("roc-stable", ["scripts/runtime.roc", "--", "install-candidate", candidate])
	} else {
		run!("roc-stable", ["scripts/runtime.roc", "--", "fetch"].concat(musl.join_map(|target| ["--target", target])))
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
	Path.write_utf8!(Path.join(directory, "libhost.a.sha256"), host_digest!(Path.join(directory, "libhost.a"))?)?
	Script.info!("HOST", "platform/targets/${target}/libhost.a")
}

host_digest! = |path| {
	bytes = Script.command("sha256sum").capture!([Path.to_os_str(path)], Path.utf8("."), [])?
	Ok(Str.from_utf8_lossy(bytes).split_on(" ").first()?.concat("\n"))
}

run! = |program, args| Script.command(program).run!(args.map(OsStr.from_str))

cli_parser = Cli.assert_valid(
	Cli.finish(
		{
			skip_host: Opt.flag({ short: "", long: "skip-host", help: "Verify/install linker inputs without compiling cached hosts." }),
			target: Opt.str({ short: "", long: "target", help: "native (default), all, or one of x64mac, arm64mac, x64musl, arm64musl.", default: Value("native") }),
			runtime_candidate: Opt.str({ short: "", long: "runtime-candidate", help: "Unpublished linker-input archive to install instead of the release.", default: Value("") }),
		}.Cli,
		{ name: "build-platform", version: "development", authors: [], description: "Build the Rust host for the platform targets.", text_style: Plain },
	),
)
