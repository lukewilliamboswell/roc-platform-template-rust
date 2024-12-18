use roc_std::{RocRefcounted, RocStr};

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct Ast {
    pub defs: RocStr,
    pub header: RocStr,
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
