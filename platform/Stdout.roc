module [
    Err,
    line!,
]

import Host

## **NotFound** - An entity was not found, often a file.
##
## **PermissionDenied** - The operation lacked the necessary privileges to complete.
##
## **BrokenPipe** - The operation failed because a pipe was closed.
##
## **AlreadyExists** - An entity already exists, often a file.
##
## **Interrupted** - This operation was interrupted. Interrupted operations can typically be retried.
##
## **Unsupported** - This operation is unsupported on this platform. This means that the operation can never succeed.
##
## **OutOfMemory** - An operation could not be completed, because it failed to allocate enough memory.
##
## **Other** - A custom error that does not fall under any other I/O error kind.
Err : [
    NotFound,
    PermissionDenied,
    BrokenPipe,
    AlreadyExists,
    Interrupted,
    Unsupported,
    OutOfMemory,
    Other Str,
]

## Write the given string to [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)),
## followed by a newline.
line! : Str => Result {} [StdoutErr Err]
line! = \str ->
    Host.stdout_line! str
    |> Result.mapErr \internal_err ->
        when internal_err.tag is
            NotFound -> StdoutErr NotFound
            PermissionDenied -> StdoutErr PermissionDenied
            BrokenPipe -> StdoutErr BrokenPipe
            AlreadyExists -> StdoutErr AlreadyExists
            Interrupted -> StdoutErr Interrupted
            Unsupported -> StdoutErr Unsupported
            OutOfMemory -> StdoutErr OutOfMemory
            Other | EndOfFile -> StdoutErr (Other internal_err.msg)
