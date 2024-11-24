hosted Effect
    exposes [
        InternalIOErr,
        stdoutLine!,
        log!,
    ]
    imports []

InternalIOErr : {
    tag : [
        EndOfFile,
        NotFound,
        PermissionDenied,
        BrokenPipe,
        AlreadyExists,
        Interrupted,
        Unsupported,
        OutOfMemory,
        Other,
    ],
    msg : Str,
}

stdoutLine! : Str => Result {} InternalIOErr

log! : Str => {}
