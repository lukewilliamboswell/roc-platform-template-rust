use crate::CommentOrNewline;
use roc_std::{roc_refcounted_noop_impl, RocList, RocRefcounted, RocStr};

#[derive(Debug)]
#[repr(C)]
pub struct SpaceAfter {
    pub f0: Spaced,
    pub f1: RocList<CommentOrNewline>,
}

impl RocRefcounted for SpaceAfter {
    fn inc(&mut self) {
        self.f0.inc();
        self.f1.inc();
    }
    fn dec(&mut self) {
        self.f0.dec();
        self.f1.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[derive(Clone, Copy)]
#[repr(u8)]
pub enum Discriminant {
    Item = 0,
    SpaceAfter = 1,
    SpaceBefore = 2,
}

impl core::fmt::Debug for Discriminant {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::Item => f.write_str("Spaced::Item"),
            Self::SpaceAfter => f.write_str("Spaced::SpaceAfter"),
            Self::SpaceBefore => f.write_str("Spaced::SpaceBefore"),
        }
    }
}

roc_refcounted_noop_impl!(Discriminant);

#[repr(transparent)]
pub struct Spaced(*mut Union);

impl Spaced {
    pub fn discriminant(&self) -> Discriminant {
        let discriminants = {
            use Discriminant::*;

            [Item, SpaceAfter, SpaceBefore]
        };

        if self.0.is_null() {
            unreachable!("this pointer cannot be NULL")
        } else {
            match std::mem::size_of::<usize>() {
                4 => discriminants[self.0 as usize & 0b011],
                8 => discriminants[self.0 as usize & 0b111],
                _ => unreachable!(),
            }
        }
    }

    fn unmasked_pointer(&self) -> *mut Union {
        debug_assert!(!self.0.is_null());

        let mask = match std::mem::size_of::<usize>() {
            4 => !0b011usize,
            8 => !0b111usize,
            _ => unreachable!(),
        };

        ((self.0 as usize) & mask) as *mut Union
    }

    unsafe fn ptr_read_union(&self) -> core::mem::ManuallyDrop<Union> {
        let ptr = self.unmasked_pointer();

        core::mem::ManuallyDrop::new(unsafe { std::ptr::read(ptr) })
    }
}

impl core::fmt::Debug for Spaced {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        use Discriminant::*;

        match self.discriminant() {
            Item => {
                let payload_union = unsafe { self.ptr_read_union() };

                unsafe {
                    f.debug_tuple("Spaced::Item")
                        .field(&payload_union.item.f0)
                        .finish()
                }
            }
            SpaceAfter => {
                let payload_union = unsafe { self.ptr_read_union() };

                unsafe {
                    f.debug_tuple("Spaced::SpaceAfter")
                        .field(&payload_union.space_after.f0)
                        .field(&payload_union.space_after.f1)
                        .finish()
                }
            }
            SpaceBefore => {
                let payload_union = unsafe { self.ptr_read_union() };

                unsafe {
                    f.debug_tuple("Spaced::SpaceBefore")
                        .field(&payload_union.space_before.f0)
                        .field(&payload_union.space_before.f1)
                        .finish()
                }
            }
        }
    }
}

#[derive(Clone, Default, Debug)]
#[repr(transparent)]
pub struct Item {
    pub f0: RocStr,
}

impl RocRefcounted for Item {
    fn inc(&mut self) {
        self.f0.inc();
    }
    fn dec(&mut self) {
        self.f0.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[repr(C)]
union Union {
    item: core::mem::ManuallyDrop<Item>,
    space_after: core::mem::ManuallyDrop<SpaceAfter>,
    space_before: core::mem::ManuallyDrop<SpaceAfter>,
}

impl RocRefcounted for Spaced {
    fn inc(&mut self) {
        unsafe {
            match self.discriminant() {
                Discriminant::Item => {
                    let mut payload_union = self.ptr_read_union();
                    payload_union.item.f0.inc();
                }
                Discriminant::SpaceAfter => {
                    let mut payload_union = self.ptr_read_union();
                    payload_union.space_after.f0.inc();
                    payload_union.space_after.f1.inc();
                }
                Discriminant::SpaceBefore => {
                    let mut payload_union = self.ptr_read_union();
                    payload_union.space_before.f0.inc();
                    payload_union.space_before.f1.inc();
                }
            }
        }
    }
    fn dec(&mut self) {
        unsafe {
            match self.discriminant() {
                Discriminant::Item => {
                    let mut payload_union = self.ptr_read_union();
                    payload_union.item.f0.dec();
                }
                Discriminant::SpaceAfter => {
                    let mut payload_union = self.ptr_read_union();
                    payload_union.space_after.f0.dec();
                    payload_union.space_after.f1.dec();
                }
                Discriminant::SpaceBefore => {
                    let mut payload_union = self.ptr_read_union();
                    payload_union.space_before.f0.dec();
                    payload_union.space_before.f1.dec();
                }
            }
        }
    }
    fn is_refcounted() -> bool {
        true
    }
}
