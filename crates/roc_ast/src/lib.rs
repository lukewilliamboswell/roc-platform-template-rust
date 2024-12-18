use roc_std::{roc_refcounted_noop_impl, RocRefcounted, RocStr};

#[derive(Clone, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct Ast {
    pub defs: RocStr,
    pub header: SpacesBefore,
}

impl RocRefcounted for Ast {
    fn inc(&mut self) {
        self.defs.inc();
        self.header.inc();
    }
    fn dec(&mut self) {
        self.defs.dec();
        self.header.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(u8)]
pub enum CommentOrNewlineTag {
    DocComment = 0,
    LineComment = 1,
    Newline = 2,
}

impl core::fmt::Debug for CommentOrNewlineTag {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::DocComment => f.write_str("CommentOrNewline::DocComment"),
            Self::LineComment => f.write_str("CommentOrNewline::LineComment"),
            Self::Newline => f.write_str("CommentOrNewline::Newline"),
        }
    }
}

roc_refcounted_noop_impl!(CommentOrNewlineTag);

#[derive(Clone, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct CommentOrNewline {
    pub str: RocStr,
    pub tag: CommentOrNewlineTag,
}

impl RocRefcounted for CommentOrNewline {
    fn inc(&mut self) {
        self.str.inc();
    }
    fn dec(&mut self) {
        self.str.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[derive(Clone, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct SpacesBefore {
    pub before: CommentOrNewline,
    pub item: RocStr,
}

impl RocRefcounted for SpacesBefore {
    fn inc(&mut self) {
        self.before.inc();
        self.item.inc();
    }
    fn dec(&mut self) {
        self.before.dec();
        self.item.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}
