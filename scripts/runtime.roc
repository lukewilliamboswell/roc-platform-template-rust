#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	roc: "nightly-2026-10-25-72704da",
}

import cli.OsStr
import cli.Path
import src/Runtime

## Fetch selected locked target archives, or inspect/install a local candidate.
main! = |args| match args.map(OsStr.display) {
	["fetch", .. as rest] => Runtime.fetch!(parse_targets(rest)?)
	["inspect", archive, target] => {
		_ = Runtime.inspect!(Path.utf8(archive), target)?
		Ok({})
	}
	["install-candidate", archive] => Runtime.install!(Path.utf8(archive), "all")
	_ => Err(Usage("runtime fetch [--target TARGET] | inspect ARCHIVE TARGET | install-candidate ARCHIVE"))
}

parse_targets = |args| match args {
	[] => Ok(Runtime.target_names)
	["--target", target] if Runtime.target_names.contains(target) => Ok([target])
	["--target", a, "--target", b] if Runtime.target_names.contains(a) and Runtime.target_names.contains(b) and a != b => Ok([a, b])
	_ => Err(InvalidTargets)
}
