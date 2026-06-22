app [main!] { pf: platform "https://github.com/lukewilliamboswell/roc-platform-template-rust/releases/download/0.4/3q9Kou2yUcPovfn1NhRrsvtcdfHUWmzyCaGwiupYFXUk.tar.zst" }

import pf.Stdout
import pf.Stderr

# Demonstrates: Stderr output, both output streams

main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| {
    # Write to stdout
    Stdout.line!("This message goes to stdout")
    Stdout.line!("You can redirect it with: roc run example.roc > out.txt")

    # Write to stderr
    Stderr.line!("This message goes to stderr")
    Stderr.line!("You can redirect it with: roc run example.roc 2> err.txt")

    # Return success
    Ok({})
}
