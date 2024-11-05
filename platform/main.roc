platform ""
    requires {} { main! : {} => Result {} [Exit I32 Str]_ }
    exposes [Stdout]
    packages {}
    imports [Stdout]
    provides [mainForHost!]


mainForHost! : {} => Result {} I32
mainForHost! = \_ ->
    when main! is
        Ok {} -> Ok {}
        Err (Exit code str) ->
            if Str.isEmpty str then
                Err code
            else
                Stdout.line! str
                Err code
        Err err ->
            Stdout.line! "Program exited early with error: $(Inspect.toStr err)"
            Err 1
