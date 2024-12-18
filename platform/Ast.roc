module [Ast]

Ast : {
    header : SpacesBefore Str,
    defs : Str,
}

SpacesBefore item : {
    before : CommentOrNewline,
    item : item,
}

CommentOrNewline : {
    tag : [Newline, LineComment, DocComment],
    str : Str,
}
