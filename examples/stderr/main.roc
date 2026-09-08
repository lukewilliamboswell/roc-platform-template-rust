app [main!] { roc: "nightly-2026-09-05-b195f5b", pf: platform "https://github.com/lukewilliamboswell/roc-platform-template-rust/releases/download/1.1.0/BqAtivonrp6omZf8pQLHed3JtdE5TuaWT3ybEgWrLDZ.tar.zst" }

import pf.Stdout
import pf.Stderr

# Demonstrates: Stderr output, both output streams

main! : List(Str) => Try({}, [Exit(I32), StderrErr(Str), StdoutErr(Str), ..])
main! = |_args| {
	# Write to stdout
	Stdout.line!("This message goes to stdout")?
	Stdout.line!("You can redirect it with: roc run example.roc > out.txt")?

	# Write to stderr
	Stderr.line!("This message goes to stderr")?
	Stderr.line!("You can redirect it with: roc run example.roc 2> err.txt")?

	# Return success
	Ok({})
}
