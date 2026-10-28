#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	roc: "nightly-2026-10-25-72704da",
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
