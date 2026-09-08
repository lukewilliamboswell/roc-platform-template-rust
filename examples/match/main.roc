app [main!] { roc: "nightly-2026-09-05-b195f5b", pf: platform "https://github.com/lukewilliamboswell/roc-platform-template-rust/releases/download/1.0.0/Bu7FVf57VbTwUrUSumuTmQNMJLLmGBmer6L5AarS4qnV.tar.zst" }

import pf.Stdout

# Demonstrates: match expressions on booleans

main! : List(Str) => Try({}, [Exit(I32), StdoutErr(Str), ..])
main! = |args| {
	# Pattern match on booleans derived from command-line input
	no_extra_args = args.len() == 1
	has_extra_args = args.len() > 1

	result1 = match no_extra_args {
		True => "yes"
		False => "no"
	}
	Stdout.line!("match no extra args: ${result1}")?

	result2 = match has_extra_args {
		True => "yes"
		False => "no"
	}
	Stdout.line!("match extra args: ${result2}")?

	Ok({})
}
