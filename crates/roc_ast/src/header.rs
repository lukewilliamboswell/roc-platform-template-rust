#![allow(dead_code)]
use crate::{CommentOrNewline, Loc};
use core::mem::ManuallyDrop;
use roc_std::{roc_refcounted_noop_impl, RocList, RocRefcounted, RocResult, RocStr};

#[repr(C)]
pub struct Header {
    payload: UnionHeader,
    discriminant: DiscriminantHeader,
}

impl<'a> From<roc_parse::ast::Header<'a>> for Header {
    fn from(_value: roc_parse::ast::Header) -> Self {
        // TODO
        Header {
            discriminant: DiscriminantHeader::App,
            payload: UnionHeader {
                app: ManuallyDrop::new("SOME HEADER".into()),
            },
        }
    }
}

#[derive(Clone, Copy)]
#[repr(u8)]
pub enum DiscriminantHeader {
    App = 0,
    Hosted = 1,
    Module = 2,
    Package = 3,
    Platform = 4,
}

impl core::fmt::Debug for DiscriminantHeader {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::App => f.write_str("Header::App"),
            Self::Hosted => f.write_str("Header::Hosted"),
            Self::Module => f.write_str("Header::Module"),
            Self::Package => f.write_str("Header::Package"),
            Self::Platform => f.write_str("Header::Platform"),
        }
    }
}

roc_refcounted_noop_impl!(DiscriminantHeader);

#[repr(C, align(8))]
pub union UnionHeader {
    app: ManuallyDrop<RocStr>,
    hosted: ManuallyDrop<RocStr>,
    module: ManuallyDrop<ModuleHeader>,
    package: ManuallyDrop<RocStr>,
    platform: ManuallyDrop<RocStr>,
}

impl Header {
    /// Returns which variant this tag union holds. Note that this never includes a payload!
    pub fn discriminant(&self) -> DiscriminantHeader {
        unsafe {
            let bytes = core::mem::transmute::<&Self, &[u8; core::mem::size_of::<Self>()]>(self);

            core::mem::transmute::<u8, DiscriminantHeader>(*bytes.as_ptr().add(56))
        }
    }

    /// Internal helper
    fn set_discriminant(&mut self, discriminant: DiscriminantHeader) {
        let discriminant_ptr: *mut DiscriminantHeader = (self as *mut Header).cast();

        unsafe {
            *(discriminant_ptr.add(56)) = discriminant;
        }
    }
}

impl Clone for Header {
    fn clone(&self) -> Self {
        use DiscriminantHeader::*;

        let payload = unsafe {
            match self.discriminant {
                App => UnionHeader {
                    app: self.payload.app.clone(),
                },
                Hosted => UnionHeader {
                    hosted: self.payload.hosted.clone(),
                },
                Module => UnionHeader {
                    module: self.payload.module.clone(),
                },
                Package => UnionHeader {
                    package: self.payload.package.clone(),
                },
                Platform => UnionHeader {
                    platform: self.payload.platform.clone(),
                },
            }
        };

        Self {
            discriminant: self.discriminant,
            payload,
        }
    }
}

impl core::fmt::Debug for Header {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        use DiscriminantHeader::*;

        unsafe {
            match self.discriminant {
                App => {
                    let field: &RocStr = &self.payload.app;
                    f.debug_tuple("Header::App").field(field).finish()
                }
                Hosted => {
                    let field: &RocStr = &self.payload.hosted;
                    f.debug_tuple("Header::Hosted").field(field).finish()
                }
                Module => {
                    let field: &crate::ModuleHeader = &self.payload.module;
                    f.debug_tuple("Header::Module").field(field).finish()
                }
                Package => {
                    let field: &RocStr = &self.payload.package;
                    f.debug_tuple("Header::Package").field(field).finish()
                }
                Platform => {
                    let field: &RocStr = &self.payload.platform;
                    f.debug_tuple("Header::Platform").field(field).finish()
                }
            }
        }
    }
}

impl Drop for Header {
    fn drop(&mut self) {
        unsafe {
            match self.discriminant() {
                DiscriminantHeader::App => ManuallyDrop::drop(&mut self.payload.app),
                DiscriminantHeader::Hosted => ManuallyDrop::drop(&mut self.payload.hosted),
                DiscriminantHeader::Module => ManuallyDrop::drop(&mut self.payload.module),
                DiscriminantHeader::Package => ManuallyDrop::drop(&mut self.payload.package),
                DiscriminantHeader::Platform => ManuallyDrop::drop(&mut self.payload.platform),
            }
        }
    }
}

impl RocRefcounted for Header {
    fn inc(&mut self) {
        unsafe {
            match self.discriminant() {
                DiscriminantHeader::App => (*self.payload.app).inc(),
                DiscriminantHeader::Hosted => (*self.payload.hosted).inc(),
                DiscriminantHeader::Module => (*self.payload.module).inc(),
                DiscriminantHeader::Package => (*self.payload.package).inc(),
                DiscriminantHeader::Platform => (*self.payload.platform).inc(),
            }
        }
    }
    fn dec(&mut self) {
        unsafe {
            match self.discriminant() {
                DiscriminantHeader::App => (*self.payload.app).dec(),
                DiscriminantHeader::Hosted => (*self.payload.hosted).dec(),
                DiscriminantHeader::Module => (*self.payload.module).dec(),
                DiscriminantHeader::Package => (*self.payload.package).dec(),
                DiscriminantHeader::Platform => (*self.payload.platform).dec(),
            }
        }
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[derive(Clone, Debug)]
#[repr(C)]
pub struct ModuleHeader {
    pub after_keyword: RocList<CommentOrNewline>,
    pub exposes: RocList<Loc>,
    pub params: RocResult<(), ()>,
}

impl RocRefcounted for ModuleHeader {
    fn inc(&mut self) {
        self.after_keyword.inc();
        self.exposes.inc();
    }
    fn dec(&mut self) {
        self.after_keyword.dec();
        self.exposes.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}
