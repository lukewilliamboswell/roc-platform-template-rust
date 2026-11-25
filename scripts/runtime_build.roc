#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	roc: "nightly-2026-11-25-d5a4f1e",
}

import cli.OsStr
import src/RuntimeProducer

main! = |args| match args.map(OsStr.display) {
	["build"] => RuntimeProducer.build!("dist/runtime")
	["build", "--output", directory] => RuntimeProducer.build!(directory)
	["prepare-release"] => RuntimeProducer.prepare!("dist/runtime")
	["prepare-release", "--directory", directory] => RuntimeProducer.prepare!(directory)
	_ => Err(Usage("runtime-build build [--output directory] | prepare-release [--directory directory]"))
}
