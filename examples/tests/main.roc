app [main!] { roc: "nightly-2026-09-05-b195f5b", pf: platform "https://github.com/lukewilliamboswell/roc-platform-template-rust/releases/download/1.0.0/Bu7FVf57VbTwUrUSumuTmQNMJLLmGBmer6L5AarS4qnV.tar.zst" }

import pf.Stdout

# Demonstrates: expect keyword for testing
# Run with: roc test examples/tests/main.roc

main! : List(Str) => Try({}, [Exit(I32), StdoutErr(Str), ..])
main! = |_args| {
	Stdout.line!("Run 'roc test --verbose examples/tests/main.roc' to execute the tests")?
	Ok({})
}

# --- Simple expects for demonstration ---

## Addition works for integers.
expect 1 + 1 == 2

## Subtraction works for integers.
expect 10 - 3 == 7

## Multiplication works for integers.
expect 4 * 5 == 20

## True compares equal to itself.
expect True == True

## False compares equal to itself.
expect False == False

## True and False are distinct values.
expect True != False

## String concatenation combines both inputs in order.
expect Str.concat("Hello", " World") == "Hello World"

## The empty string reports as empty.
expect Str.is_empty("")

## Non-empty strings do not report as empty.
expect Str.is_empty("hi") == False
