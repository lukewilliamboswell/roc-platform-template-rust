module [Ast]

Ast : {
    header : SpacesBefore Header,
    defs : Str,
}

SpacesBefore a : {
    before : List CommentOrNewline,
    item : a,
}

CommentOrNewline : {
    tag : [Newline, LineComment, DocComment],
    str : Str,
}

Header : [
    Module ModuleHeader,
    App Str,
    Package Str,
    Platform Str,
    Hosted Str,
]

ModuleHeader : {
    after_keyword : List CommentOrNewline,
    params : Result {} {}, # todo module params
    exposes : List (Loc (Spaced Str)),
}

Loc a : {
    region : Region,
    value : a,
}

Region : {
    start : Position,
    end : Position,
}

Position : {
    offset : U32,
}

Spaced a : [
    Item a,
    SpaceBefore (Spaced a) (List CommentOrNewline),
    SpaceAfter (Spaced a) (List CommentOrNewline),
]
