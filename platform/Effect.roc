# this module will be replaced when effect interpreters are implemented
hosted Effect
    exposes [
        stdoutLine!,
        log!,
    ]
    imports []

# effects that are provided by the host
stdoutLine! : Str => Result {} Str

log! : Str => {}
