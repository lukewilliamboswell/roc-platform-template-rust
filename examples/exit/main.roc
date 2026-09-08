app [main!] { roc: "nightly-2026-09-05-b195f5b", pf: platform "https://github.com/lukewilliamboswell/roc-platform-template-rust/releases/download/1.0.0/Bu7FVf57VbTwUrUSumuTmQNMJLLmGBmer6L5AarS4qnV.tar.zst" }

import pf.Stdout

main! : List(Str) => Try({}, [Exit(I32), StdoutErr(Str), ..])
main! = |_args| {
	Stdout.line!("This example exits with a non-zero exit code")?
	Err(Exit(23))
}
