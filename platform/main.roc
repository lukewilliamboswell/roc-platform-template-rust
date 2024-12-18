platform ""
    requires {} { main! : Ast => Result {} [Exit I32 Str]_ }
    exposes [Stdout, Ast]
    packages {}
    imports []
    provides [main_for_host!]

import Host
import Ast exposing [Ast]

main_for_host! : Ast => I32
main_for_host! = \ast ->
    when main! ast is
        Ok {} -> 0
        Err (Exit code str) ->
            if Str.isEmpty str then
                code
            else
                Host.log! str
                code

        Err other ->
            Host.log! "Program exited early with error: $(Inspect.toStr other)"
            1
