use roc_std::{RocList, RocStr};
use std::borrow::Borrow;
use std::ffi::c_char;

/// # Safety
/// This function is the entry point for the program, it will be linked by roc using the legacy linker
/// to produce the final executable.
///
/// Note we use argc and argv to pass arguments to the program instead of std::env::args().
#[no_mangle]
pub unsafe extern "C" fn main(argc: usize, argv: *const *const i8) -> i32 {
    let args = std::slice::from_raw_parts(argv, argc);

    let args: RocList<RocStr> = args
        .iter()
        .map(|&c_ptr| {
            let c_str = std::ffi::CStr::from_ptr(c_ptr as *const c_char);
            RocStr::from(c_str.to_string_lossy().borrow())
        })
        .collect();

    roc_host::rust_main(args)
}
