hosted [
    InternalIOErr,
    stdout_line!,
    log!,
]

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

stdout_line! : Str => Result {} InternalIOErr

log! : Str => {}
