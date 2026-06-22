app [main!] { pf: platform "https://github.com/lukewilliamboswell/roc-platform-template-rust/releases/download/0.4/3q9Kou2yUcPovfn1NhRrsvtcdfHUWmzyCaGwiupYFXUk.tar.zst" }

import pf.Stdin
import pf.Stdout

# Demonstrates: Stdin.line!, interactive I/O, effectful functions

main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| {
    Stdout.line!("Enter something and I'll echo it back:")

    input = Stdin.line!()
    Stdout.line!("You entered: ${input}")

    Ok({})
}
