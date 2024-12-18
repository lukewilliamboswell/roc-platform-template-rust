mod header;
mod spaced;

use crate::header::{Header, ModuleHeader};
use crate::spaced::Spaced;
use roc_std::{roc_refcounted_noop_impl, RocList, RocRefcounted, RocStr};

#[derive(Clone, Debug)]
#[repr(C)]
pub struct Ast {
    pub defs: RocStr,
    pub header: SpacesBefore<Header>,
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

#[derive(Clone, Copy)]
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

#[derive(Clone, Debug)]
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

#[derive(Clone, Debug)]
#[repr(C)]
pub struct SpacesBefore<T> {
    pub before: RocList<CommentOrNewline>,
    pub item: T,
}

impl<T> RocRefcounted for SpacesBefore<T>
where
    T: RocRefcounted,
{
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

#[derive(Clone, Copy, Default, Debug)]
#[repr(transparent)]
pub struct Position {
    pub offset: u32,
}

roc_refcounted_noop_impl!(Position);

#[derive(Clone, Copy, Default, Debug)]
#[repr(C)]
pub struct Region {
    pub end: Position,
    pub start: Position,
}

roc_refcounted_noop_impl!(Region);

#[derive(Debug)]
#[repr(C)]
pub struct Loc {
    pub value: Spaced,
    pub region: Region,
}

impl RocRefcounted for Loc {
    fn inc(&mut self) {
        self.value.inc();
    }
    fn dec(&mut self) {
        self.value.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}
