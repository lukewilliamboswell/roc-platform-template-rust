use roc_std::roc_refcounted_noop_impl;
use roc_std::RocRefcounted;

#[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(u8)]
pub enum IOErrTag {
    BrokenPipe = 0,
    Interrupted = 1,
    Other = 2,
    OutOfMemory = 3,
    Unsupported = 4,
    WouldBlock = 5,
    WriteZero = 6,
}

impl core::fmt::Debug for IOErrTag {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::BrokenPipe => f.write_str("BrokenPipe"),
            Self::Interrupted => f.write_str("Interrupted"),
            Self::Other => f.write_str("Other"),
            Self::OutOfMemory => f.write_str("OutOfMemory"),
            Self::Unsupported => f.write_str("Unsupported"),
            Self::WouldBlock => f.write_str("WouldBlock"),
            Self::WriteZero => f.write_str("WriteZero"),
        }
    }
}

roc_refcounted_noop_impl!(IOErrTag);

#[derive(Clone, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct IOErr {
    pub msg: roc_std::RocStr,
    pub tag: IOErrTag,
}

impl roc_std::RocRefcounted for IOErr {
    fn inc(&mut self) {
        self.msg.inc();
    }
    fn dec(&mut self) {
        self.msg.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

impl From<std::io::Error> for IOErr {
    fn from(io_err: std::io::Error) -> Self {
        match io_err.kind() {
            std::io::ErrorKind::BrokenPipe => Self {
                msg: roc_std::RocStr::empty(),
                tag: IOErrTag::BrokenPipe,
            },
            std::io::ErrorKind::WouldBlock => Self {
                msg: roc_std::RocStr::empty(),
                tag: IOErrTag::WouldBlock,
            },
            std::io::ErrorKind::WriteZero => Self {
                msg: roc_std::RocStr::empty(),
                tag: IOErrTag::WriteZero,
            },
            std::io::ErrorKind::Unsupported => Self {
                msg: roc_std::RocStr::empty(),
                tag: IOErrTag::Unsupported,
            },
            std::io::ErrorKind::Interrupted => Self {
                msg: roc_std::RocStr::empty(),
                tag: IOErrTag::Interrupted,
            },
            std::io::ErrorKind::OutOfMemory => Self {
                msg: roc_std::RocStr::empty(),
                tag: IOErrTag::OutOfMemory,
            },
            _ => Self {
                msg: roc_std::RocStr::from(format!("{:?}", io_err).as_str()),
                tag: IOErrTag::Other,
            },
        }
    }
}
