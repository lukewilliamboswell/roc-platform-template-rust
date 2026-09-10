app [main!] { roc: "nightly-2026-09-10-a670e34", pf: platform "https://github.com/lukewilliamboswell/roc-platform-template-rust/releases/download/1.1.0/BqAtivonrp6omZf8pQLHed3JtdE5TuaWT3ybEgWrLDZ.tar.zst" }

import pf.Stdin
import pf.Stdout

# Demonstrates: Stdin.line!, interactive I/O, effectful functions

main! : List(Str) => Try({}, [Exit(I32), StdinErr(Str), StdoutErr(Str), ..])
main! = |_args| {
	Stdout.line!("Enter something and I'll echo it back:")?

	input = Stdin.line!({})?
	Stdout.line!("You entered: ${input}")?

	Ok({})
}
