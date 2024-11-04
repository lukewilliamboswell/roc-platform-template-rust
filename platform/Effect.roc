# this module will be replaced when effect interpreters are implemented
hosted Effect
    exposes [
        stdoutLine,
    ]
    imports []

# effects that are provided by the host
stdoutLine : Str -> Task {} Str
