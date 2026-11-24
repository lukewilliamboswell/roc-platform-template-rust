#!/usr/bin/env roc-stable
app [main!] {
	ansi: "https://github.com/lukewilliamboswell/roc-ansi/releases/download/0.13.0/JXLM47L6CzrLXB5HBfqc27VnU6CD4jMm5Mk6dgbbovL.tar.zst",
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	roc: "nightly-2026-11-24-ff5e544",
}

## `roc test` needs an app header to resolve imported cli modules. Keep the
## pure tooling module tests reachable from this single pinned test application.
import src/Files
import src/HostFingerprint
import src/ReleaseArtifacts
import src/RocSource
import src/RuntimeProducer

main! = |_args| Ok({})

expect Files.stem("main.roc") == "main"
expect HostFingerprint.includes("src/lib.rs")
expect RocSource.app_header("package [] {}") == Ok([])
