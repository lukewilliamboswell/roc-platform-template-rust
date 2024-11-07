# this module will be replaced when effect interpreters are implemented
hosted Effect
    exposes [
        InternalIOErr,
        stdoutLine!,
        log!,
    ]
    imports []

InternalIOErr : {
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


# effects that are provided by the host
stdoutLine! : Str => Result {} InternalIOErr

log! : Str => {}
