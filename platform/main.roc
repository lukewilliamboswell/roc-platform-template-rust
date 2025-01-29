platform ""
    requires {} { main! : {} => Result {} [Exit I32 Str]_ }
    exposes [Stdout]
    packages {}
    imports []
    provides [main_for_host!]

import Effect

main_for_host! : I32 => I32
main_for_host! = |_|
    when main!({}) is
        Ok({}) -> 0
        Err(Exit(code, str)) ->
            if Str.is_empty(str) then
                code
            else
                Effect.log!(str)
                code

        Err(other) ->
            Effect.log!("Program exited early with error: ${Inspect.to_str(other)}")
            1
