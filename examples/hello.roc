app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout

main! : {} => Result {} _
main! = \{} ->
    Stdout.line! "Roc loves Rust"
