app [config] { pf: platform "https://github.com/lukewilliamboswell/roc-blueprint/releases/download/0.8.0/FbJymjYdCxx9vqMcau7r4tQfeAbnVGqqJoYrLGqPCqKu.tar.zst" }

# Two compilers are in play. `roc-stable` is the pinned nightly that runs the
# repository tooling in scripts/; its tag matches every script header. The
# platform and examples use whichever `roc` is on PATH, normally the latest
# nightly, so Blueprint deliberately provides no bare `roc`. The Rust host
# toolchain comes from rust-toolchain.toml via rustup.

config = [
	Name("roc-platform-template-rust"),
	Systems(["x86_64-linux", "aarch64-linux", "aarch64-darwin"]),
	Packages("nix", From(NixPackages("github:NixOS/nixpkgs/nixos-unstable"))),
	Input("roc", "github:roc-lang/roc-overlay"),
	Input("zig", "github:mitchellh/zig-overlay"),
	Environment(
		"dev",
		[
			Overlays(["roc", "zig"]),
			Command("roc-stable", "nix#rocpkgs.nightly-2026-10-25-72704da"),
			# Every bundle the scripts depend on: `roc-stable deps scripts/check_all.roc`.
			RocPackages([
				"https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
				"https://github.com/lukewilliamboswell/roc-ansi/releases/download/0.13.0/JXLM47L6CzrLXB5HBfqc27VnU6CD4jMm5Mk6dgbbovL.tar.zst",
				"https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst",
			]),
			Tools(["nix#coreutils", "nix#gh", "nix#git", "nix#unzip", "nix#zip", "nix#zigpkgs.\"0.16.0\""]),
		],
	),
	Shell("default", [Use("dev")]),
	Task("check", [Use("dev"), Run(["scripts/check_all.roc"])]),
	Task("build-platform", [Use("dev"), Run(["scripts/build_platform.roc", "--"])]),
	Task("bundle", [Use("dev"), Run(["scripts/bundle.roc", "--"])]),
	Task("examples", [Use("dev"), Run(["scripts/examples.roc", "--"])]),
	Task("stable-version", [Use("dev"), Run(["roc-stable", "version"])]),
]
