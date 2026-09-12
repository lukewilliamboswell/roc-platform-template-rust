app [main!] { roc: "nightly-2026-09-12-220fd47", pf: platform "https://github.com/lukewilliamboswell/roc-platform-template-rust/releases/download/1.1.0/BqAtivonrp6omZf8pQLHed3JtdE5TuaWT3ybEgWrLDZ.tar.zst" }

import pf.Stdout

# Demonstrates: fold, pure functions, lambdas
# NOTE: Some fold operations with numbers have compiler bugs

main! : List(Str) => Try({}, [Exit(I32), StdoutErr(Str), ..])
main! = |_args| {
	# Build a string using fold - concatenate list items
	joined = ["Hello", " ", "World", "!"].fold("", |acc, s| Str.concat(acc, s))
	Stdout.line!("Joined: ${joined}")?

	# Use Str.join_with for joining with separator
	csv = Str.join_with(["apple", "banana", "cherry"], ", ")
	Stdout.line!("Fruits: ${csv}")?

	Ok({})
}
