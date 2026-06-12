//! Roc platform host implementation for Roc's symbol-based host ABI.
//!
//! This host provides memory management and I/O effects for Roc programs.

use std::ffi::c_void;
use std::io::{self, BufRead, Write};

mod roc_platform_abi;

use crate::roc_platform_abi::{
    make_roc_ops, DefaultAllocators, DefaultHandlers, HostedFunctions, RocList, RocOps, RocStr,
};

// External symbol provided by the compiled Roc application
extern "C" {
    fn roc_main(args: RocList<RocStr>) -> i32;
}

static mut ROC_OPS: *mut RocOps = core::ptr::null_mut();

fn set_roc_ops(roc_ops: *mut RocOps) {
    unsafe {
        ROC_OPS = roc_ops;
    }
}

fn roc_ops_ptr() -> *mut RocOps {
    unsafe {
        if ROC_OPS.is_null() {
            eprintln!("roc host error: RocOps not initialized");
            std::process::exit(1);
        }
        ROC_OPS
    }
}

fn roc_ops() -> &'static RocOps {
    unsafe { &*roc_ops_ptr() }
}

/// Hosted function: Stderr.line!
#[no_mangle]
pub extern "C" fn roc_stderr_line(message: RocStr) {
    let _ = writeln!(io::stderr(), "{}", message.as_str());
    message.decref(roc_ops());
}

/// Hosted function: Stdin.line!
#[no_mangle]
pub extern "C" fn roc_stdin_line() -> RocStr {
    let stdin = io::stdin();
    let mut line = String::new();

    match stdin.lock().read_line(&mut line) {
        Ok(_) => {
            let trimmed = line.trim_end_matches('\n').trim_end_matches('\r');
            RocStr::from_str(trimmed, roc_ops())
        }
        Err(_) => RocStr::empty(),
    }
}

/// Hosted function: Stdout.line!
#[no_mangle]
pub extern "C" fn roc_stdout_line(message: RocStr) {
    let _ = writeln!(io::stdout(), "{}", message.as_str());
    message.decref(roc_ops());
}

#[no_mangle]
pub extern "C" fn roc_alloc(length: usize, alignment: usize) -> *mut c_void {
    DefaultAllocators::roc_alloc(roc_ops_ptr(), length, alignment)
}

#[no_mangle]
pub extern "C" fn roc_dealloc(ptr: *mut c_void, alignment: usize) {
    DefaultAllocators::roc_dealloc(roc_ops_ptr(), ptr, alignment);
}

#[no_mangle]
pub extern "C" fn roc_realloc(
    ptr: *mut c_void,
    new_length: usize,
    alignment: usize,
) -> *mut c_void {
    DefaultAllocators::roc_realloc(roc_ops_ptr(), ptr, new_length, alignment)
}

#[no_mangle]
pub extern "C" fn roc_dbg(bytes: *const u8, len: usize) {
    DefaultHandlers::roc_dbg(roc_ops_ptr(), bytes, len);
}

#[no_mangle]
pub extern "C" fn roc_expect_failed(bytes: *const u8, len: usize) {
    DefaultHandlers::roc_expect_failed(roc_ops_ptr(), bytes, len);
}

#[no_mangle]
pub extern "C" fn roc_crashed(bytes: *const u8, len: usize) {
    DefaultHandlers::roc_crashed(roc_ops_ptr(), bytes, len);
}

/// Build a RocList<RocStr> from command-line arguments.
fn build_args_list(roc_ops: &RocOps) -> RocList<RocStr> {
    let args: Vec<String> = std::env::args().collect();

    if args.is_empty() {
        return RocList::empty();
    }

    let list = RocList::<RocStr>::allocate(args.len(), roc_ops);
    let elements = list.elements;
    for (i, arg) in args.iter().enumerate() {
        let roc_str = RocStr::from_str(arg, roc_ops);
        unsafe {
            elements.add(i).write(roc_str);
        }
    }
    list
}

/// C-compatible main entry point for the Roc program.
/// This is exported so the linker can find it.
#[no_mangle]
pub extern "C" fn main(_argc: i32, _argv: *const *const i8) -> i32 {
    rust_main()
}

/// Main entry point for the Roc program.
pub fn rust_main() -> i32 {
    let hosted_fns = HostedFunctions {
        count: 0,
        fns: core::ptr::null(),
    };

    let mut roc_ops = make_roc_ops(core::ptr::null_mut(), hosted_fns);
    set_roc_ops(&mut roc_ops);

    let args_list = build_args_list(&roc_ops);

    let exit_code = unsafe { roc_main(args_list) };
    set_roc_ops(core::ptr::null_mut());
    exit_code
}
