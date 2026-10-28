app [config] { pf: platform "https://github.com/lukewilliamboswell/roc-blueprint/releases/download/0.8.0/FbJymjYdCxx9vqMcau7r4tQfeAbnVGqqJoYrLGqPCqKu.tar.zst" }

# Two compilers are in play. `roc-stable` is the pinned nightly that runs the
# repository tooling in scripts/; its tag matches every script header. The
# platform and examples use whichever `roc` is on PATH, normally the latest
# nightly, so Blueprint deliberately provides no bare `roc`. The Rust host
# toolchain comes from rust-toolchain.toml via rustup.

import pf.Recipes

tooling = { compiler: "nightly-2026-10-25-72704da" }

repository_policy = { schema_version: 2, roots: ["platform", "examples", "scripts"], test_roots: ["platform"], profiles: [{ name: "repository", path: "tests/repository-policy.roc.txt", definition: "profile", sha256: "9124908a4afb6274ba7b9c18749b95c7d74be7992adadafe30085b33667f3303" }] }

config = [
	Name("roc-platform-template-rust"),
	Systems(["x86_64-linux", "aarch64-linux", "aarch64-darwin"]),
	Packages("nix", From(NixPackages("github:NixOS/nixpkgs/nixos-unstable"))),
	Input("roc", "github:roc-lang/roc-overlay"),
	Input("rust", "github:oxalica/rust-overlay"),
	Input("zig", "github:mitchellh/zig-overlay"),
	Environment(
		"dev",
		[
			Overlays(["roc", "zig", "rust"]),
			Programs([
				Fetch("roc-policy", Recipes.file("https://github.com/lukewilliamboswell/roc-automation/releases/download/tools-0.6.0/roc-policy-{system}")),
				Fetch("blueprint-sbom", Recipes.file("https://github.com/lukewilliamboswell/roc-blueprint/releases/download/0.8.0/blueprint-sbom-{system}")),
			]),
			Command("roc-stable", "nix#rocpkgs.nightly-2026-10-25-72704da"),
			# Every bundle the scripts depend on: `roc-stable deps scripts/check_all.roc`.
			RocPackages([
				"https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
				"https://github.com/lukewilliamboswell/roc-ansi/releases/download/0.13.0/JXLM47L6CzrLXB5HBfqc27VnU6CD4jMm5Mk6dgbbovL.tar.zst",
				"https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst",
			]),
			ToolWith("nix#rust-bin.stable.\"1.95.0\".default", [("targets", List([Str("x86_64-apple-darwin"), Str("aarch64-apple-darwin"), Str("x86_64-unknown-linux-musl"), Str("aarch64-unknown-linux-musl")])), ("extensions", List([Str("rust-src")]))]),
			Tools(["nix#python3", "nix#curl", "nix#gnutar", "nix#xz", "nix#gzip", "nix#jq", "nix#zstd", "nix#coreutils", "nix#gh", "nix#git", "nix#unzip", "nix#zip", "nix#zigpkgs.\"0.16.0\""]),
		],
	),
	Environment("docs", [Programs([Fetch("roc-docs", Recipes.file("https://github.com/lukewilliamboswell/roc-automation/releases/download/tools-0.6.0/roc-docs-{system}"))])]),
	Task("docs", [Use("docs"), Run(["roc-docs", "build", "--workspace", ".", "--output-directory", ".docs-out/manual", "--pdf-filename", "roc-platform-template-rust.pdf", "--site-url", "https://lukewilliamboswell.github.io/roc-platform-template-rust/manual/"])]),
	Task("docs-path", [Use("docs"), Run(["sh", "-c", "realpath \"$(command -v roc-docs)\""])]),
	Task("docs-site", [Use("dev"), Run(["scripts/docs_site.roc", "--"])]),
	Task("prepare-sbom", [Use("dev"), Run(["scripts/prepare_sbom.roc", "--"])]),
	Task("release-assets", [Use("dev"), Run(["scripts/release_assets.roc", "--"])]),
	Shell("default", [Use("dev")]),
	Task("bindings", [Use("dev"), Run(["scripts/bindings.roc", "--"])]),
	Task("host-fingerprint", [Use("dev"), Run(["scripts/host_fingerprint.roc", "--"])]),
	Task("runtime-build", [Use("dev"), Run(["scripts/runtime_build.roc", "--"])]),
	Task("release-evidence-test", [Use("dev"), Run(["python3", "tests/test_release_evidence.py", "--"])]),
	Task("runtime", [Use("dev"), Run(["scripts/runtime.roc", "--"])]),
	Task("runtime-cli-tests", [Use("dev"), Run(["python3", "-m", "unittest", "discover", "-s", "tests", "-p", "test_runtime_cli.py", "-v"])]),
	Task("runtime-test", [Use("dev"), Run(["scripts/runtime_test.roc", "--"])]),
	Task("tooling-tests", [Use("dev"), Run(["roc-stable", "test", "scripts/tooling_tests.roc"])]),
	Task("test-driver", [Use("dev"), Run(["python3", "tests/test_examples_driver.py"])]),
	Task("policy", [Use("dev"), Run(["roc-policy", "check", "--root", "."])]),
	Task("check", [Use("dev"), Run(["scripts/check_all.roc"])]),
	Task("check-source", [Use("dev"), Run(["scripts/check_all.roc", "--", "--static-only"])]),
	Task("build-platform", [Use("dev"), Run(["scripts/build_platform.roc", "--"])]),
	Task("bundle", [Use("dev"), Run(["scripts/bundle.roc", "--"])]),
	Task("examples", [Use("dev"), Run(["scripts/examples.roc", "--"])]),
	Task("stable-version", [Use("dev"), Run(["roc-stable", "version"])]),
]
