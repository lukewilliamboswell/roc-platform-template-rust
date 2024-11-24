app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout

main! : {} => Result {} _
main! = \{} ->

    try Stdout.line! "Roc loves Rust"

    Err (Exit 99 "SOME MESSAGE")
