app [main!] { pf: platform "https://github.com/lukewilliamboswell/roc-platform-template-rust/releases/download/0.4/3q9Kou2yUcPovfn1NhRrsvtcdfHUWmzyCaGwiupYFXUk.tar.zst" }

import pf.Stdout

main! = |_args| {
    dbg "test message"
    Stdout.line!("stdout works")
    Ok({})
}
