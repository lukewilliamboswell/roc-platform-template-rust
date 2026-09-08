app [main!] { roc: "nightly-2026-09-05-b195f5b", pf: platform "https://github.com/lukewilliamboswell/roc-platform-template-rust/releases/download/1.1.0/BqAtivonrp6omZf8pQLHed3JtdE5TuaWT3ybEgWrLDZ.tar.zst" }

import pf.Stdout

main! : List(Str) => Try({}, [Exit(I32), StdoutErr(Str), ..])
main! = |_args| {
	Stdout.line!("Hello, World!")?
	Ok({})
}
