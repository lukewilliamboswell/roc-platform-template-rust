#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	roc: "nightly-2026-10-25-72704da",
}

import cli.Env
import cli.OsStr
import cli.Path
import src/Runtime
import src/RuntimeProducer

## Link a small program exclusively against the validated candidate runtime and
## execute it on the matching Linux architecture. Never accept cross-run proof.
main! = |args| match args.map(OsStr.display) {
	["test", "--target", target] => test!("dist/runtime", target)
	["test", "--directory", directory, "--target", target] => test!(directory, target)
	_ => Err(Usage("runtime-test test [--directory DIR] --target TARGET"))
}

Toolchain : { url : Str, sha256 : Str, directory : Str }

test! = |directory, target| {
	system = Runtime.run!(["uname", "-s"])?.trim()
	arch = Runtime.run!(["uname", "-m"])?.trim()
	Runtime.require!(system == "Linux" and ((target == "x64musl" and arch == "x86_64") or (target == "arm64musl" and arch == "aarch64")), "Runtime smoke test must run on its native Linux architecture")?
	members = Runtime.inspect!(Path.utf8("${directory}/linux-runtime.tar.gz"), "all")?
	candidate_archive = Path.utf8("${directory}/linux-runtime.tar.gz")
	declared_hash = Runtime.run!(["jq", "-r", ".sha256", "${directory}/runtime-lock.proposed.json"])?.trim()
	Runtime.require!(Runtime.hex(declared_hash, 64) and Runtime.sha!(candidate_archive)? == declared_hash, "Candidate archive differs from declared digest")?
	Runtime.require!(Path.read_utf8!(Path.utf8("${directory}/SHA256SUMS"))? == "${declared_hash}  linux-runtime.tar.gz\n", "Candidate checksum file differs from archive")?
	manifest = members.keep_if(|item| item.name == "manifest.json").first()?
	sbom = Path.read_bytes!(Path.utf8("${directory}/runtime.spdx.json"))?
	created = Runtime.command!(["jq", "-r", ".creationInfo.created"], sbom)?
	created_text = Str.from_utf8_lossy(created.stdout_bytes).trim()
	Runtime.require!(created.status == Exited(0) and created_text.to_utf8().len() == 20 and created_text.ends_with("Z"), "Candidate SBOM creation time is missing")?
	Runtime.require!(Runtime.run!(["date", "-u", "-d", created_text, "+%Y-%m-%dT%H:%M:%SZ"])?.trim() == created_text, "Invalid candidate SBOM creation timestamp")?
	expected_sbom = RuntimeProducer.sbom!(manifest.bytes, declared_hash, created_text)?
	expected = Runtime.command!(["jq", "-Sc", "."], expected_sbom)?
	actual = Runtime.command!(["jq", "-Sc", "."], sbom)?
	Runtime.require!(expected.status == Exited(0) and actual.status == Exited(0) and expected.stdout_bytes == actual.stdout_bytes, "Candidate SBOM differs from verified inventory")?

	source : Runtime.Source
	source = Json.parse(Path.read_utf8!(Path.utf8("runtime/source.json"))?)?
	toolchain_json = Runtime.run!(["jq", "-c", ".${target}", "runtime/test-toolchains.json"])?
	toolchain : Toolchain
	toolchain = Json.parse(toolchain_json)?
	Runtime.require!(Runtime.hex(toolchain.sha256, 64) and toolchain.url.starts_with("https://ziglang.org/"), "Invalid native Zig toolchain pin")?
	Env.with_temp_dir!(
		|temp| {
			libraries = Path.join(temp, "libraries")
			Path.create_all!(libraries)?
			for name in Runtime.libraries {
				member = members.keep_if(|item| item.name == "targets/${target}/${name}").first()?
				Path.write_bytes!(Path.join(libraries, name), member.bytes)?
			}
			archive = Path.join(temp, "zig.tar.xz")
			_ = Runtime.run!(["curl", "--fail", "--location", "--proto", "=https", "--max-time", "120", "--output", Path.display(archive), toolchain.url])?
			Runtime.require!(Runtime.sha!(archive)? == toolchain.sha256, "Native Zig archive SHA-256 mismatch")?
			_ = Runtime.run!(["tar", "-xf", Path.display(archive), "-C", Path.display(temp)])?
			zig = Path.display(Path.join(temp, "${toolchain.directory}/zig"))
			Runtime.require!(Runtime.run!([zig, "version"])?.trim() == source.zig_version, "Native Zig version differs from source pin")?
			triple = Runtime.target_triple(target)?
			output = Path.display(Path.join(temp, "smoke"))
			cache = Path.display(Path.join(temp, "cache"))
			prefix = ["env", "-u", "ZIG_LIB_DIR", "-u", "ZIG_LIBC", "ZIG_GLOBAL_CACHE_DIR=${cache}", "ZIG_LOCAL_CACHE_DIR=${cache}/local", zig, "cc", "-target", triple]
			_ = Runtime.run!(prefix.concat(["-mcpu=baseline", "-O2", "-funwind-tables", "-c", "runtime/smoke.c", "-o", "${output}.o"]))?
			_ = Runtime.run!(prefix.concat(["-static", "-nostdlib", "${Path.display(libraries)}/crt1.o", "${output}.o", "${Path.display(libraries)}/libunwind.a", "${Path.display(libraries)}/libc.a", "${Path.display(libraries)}/libzigc.a", "${Path.display(libraries)}/libcompiler_rt.a", "-o", output]))?
			_ = Runtime.run!([output])?
			Ok({})
		},
	)
}
