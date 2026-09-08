app [main!] { roc: "nightly-2026-09-05-b195f5b", pf: platform "https://github.com/lukewilliamboswell/roc-platform-template-rust/releases/download/1.0.0/Bu7FVf57VbTwUrUSumuTmQNMJLLmGBmer6L5AarS4qnV.tar.zst" }

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
