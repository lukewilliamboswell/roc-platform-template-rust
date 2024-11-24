app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout

main! : {} => Result {} _
main! = \{} ->

    try Stdout.line! "Roc loves Rust"

    Err (SomeTag "Message" 42)
