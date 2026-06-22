app [main!] { pf: platform "https://github.com/lukewilliamboswell/roc-platform-template-rust/releases/download/0.4/3q9Kou2yUcPovfn1NhRrsvtcdfHUWmzyCaGwiupYFXUk.tar.zst" }

import pf.Stdout

main! : List(Str) => Try({}, [Exit(I32)])
main! = |args| {
    Stdout.line!("Hello Roc!")

    args_str = Str.join_with(args, ", ")
    Stdout.line!("Args: ${args_str}")

    Ok({})
}
