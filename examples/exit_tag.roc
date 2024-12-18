app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Ast exposing [Ast]

main! : Ast => Result {} _
main! = \_ast ->

    try Stdout.line! "Roc loves Rust"

    Err (SomeTag "Message" 42)
