platform ""
    requires {} { main! : _ }
    exposes []
    packages {}
    imports []
    provides [mainForHost!]

Err : {
    tag: [
        BrokenPipe,
        WouldBlock,
        WriteZero,
        Unsupported,
        Interrupted,
        OutOfMemory,
        Other,
    ],
    msg: Str,
}

mainForHost! : {} => Err
mainForHost! = main!
