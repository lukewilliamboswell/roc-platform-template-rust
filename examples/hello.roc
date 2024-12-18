app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Ast exposing [Ast]

main! : Ast  => Result {} _
main! = \ast ->
    Stdout.line!? "Roc loves Rust -- here's an AST $(Inspect.toStr ast)"

    Ok {}
