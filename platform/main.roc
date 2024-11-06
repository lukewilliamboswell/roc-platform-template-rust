platform ""
    requires {} { main! : {} => Result {} [Exit I32 Str]_ }
    exposes [Stdout]
    packages {}
    imports []
    provides [mainForHost!]

import Effect

mainForHost! : {} => Result {} I32
mainForHost! = \_ ->
    when main! {} is
        Ok {} -> Ok {}
        Err (Exit code str) ->
            if Str.isEmpty str then
                Err code
            else
                Effect.log! str
                Err code

        Err err ->
            Effect.log! "Program exited early with error: $(Inspect.toStr err)"
            Err 1
