#!/usr/bin/env roc-stable
app [main!] {
	ansi: "https://github.com/lukewilliamboswell/roc-ansi/releases/download/0.13.0/JXLM47L6CzrLXB5HBfqc27VnU6CD4jMm5Mk6dgbbovL.tar.zst",
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	roc: "nightly-2026-10-25-72704da",
}

## Write an exact host-cache key, including actual toolchain and SDK identity.
import cli.Env
import cli.OsStr
import cli.Path
import src/HostFingerprint
import src/Script
import src/Targets

main! = |_args| {
	tracked = capture!("git", ["ls-files"], [])?
	files = tracked.trim().split_on("\n").keep_if(HostFingerprint.includes)
	Script.require!(!files.is_empty(), "No host inputs were selected")?
	var $identity = "host-fingerprint-v1\nrelease --locked --lib\n${Str.join_with(Targets.all, ",")}\n"
	$identity = $identity.concat(capture!("sha256sum", files, [])?)
	for (program, args) in [("rustc", ["-vV"]), ("cargo", ["--version"]), ("uname", ["-s"]), ("uname", ["-m"])] {
		$identity = $identity.concat("${program}:\n").concat(capture!(program, args, [])?)
	}
	for name in ["RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS", "RUSTC_WRAPPER", "RUSTC_WORKSPACE_WRAPPER", "MACOSX_DEPLOYMENT_TARGET", "SDKROOT", "DEVELOPER_DIR", "ImageOS", "ImageVersion"] {
		value = Script.env_str_or!(OsStr.from_str(name), "")?
		$identity = $identity.concat("${name}=${value}\n")
	}
	build_environment = capture!("env", [], [])?.split_on("\n").keep_if(|line| ["CARGO_", "RUST", "CC=", "CXX=", "AR=", "LD=", "CFLAGS=", "CXXFLAGS=", "CPPFLAGS=", "LDFLAGS="].any(|prefix| line.starts_with(prefix)))
	$identity = $identity.concat(capture!("sort", [], Str.join_with(build_environment, "\n").to_utf8())?)
	if capture!("uname", ["-s"], [])?.trim() == "Darwin" {
		for args in [["--sdk", "macosx", "--show-sdk-path"], ["--sdk", "macosx", "--show-sdk-version"], ["--sdk", "macosx", "--show-sdk-build-version"]] {
			$identity = $identity.concat(capture!("xcrun", args, [])?)
		}
		$identity = $identity.concat(capture!("xcodebuild", ["-version"], [])?)
	}
	digest = capture!("sha256sum", [], $identity.to_utf8())?.split_on(" ").first()?
	Path.create_all!(Path.utf8(".blueprint"))?
	Path.write_utf8!(Path.utf8(".blueprint/host-fingerprint"), digest.concat("\n"))?
	Script.info!("HOST", "Fingerprint ${digest}")
}

capture! = |program, args, stdin| {
	bytes = Script.command(OsStr.from_str(program)).capture!(args.map(OsStr.from_str), Path.utf8("."), stdin)?
	Ok(Str.from_utf8_lossy(bytes))
}
