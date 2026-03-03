//! Roc platform host implementation for the new RocOps-based ABI.
//!
//! This host provides memory management and I/O effects for Roc programs.

use std::ffi::c_void;
use std::io::{self, BufRead, Write};

mod roc_platform_abi;

use crate::roc_platform_abi::{
    hosted_functions, make_roc_ops, PlatformHostedFns, RocList, RocOps, RocStr, StderrLineArgs,
    StdoutLineArgs,
};

// External symbol provided by the compiled Roc application
extern "C" {
    fn roc__main_for_host(ops: *const RocOps, ret_ptr: *mut c_void, args_ptr: *mut c_void);
}

/// Hosted function: Stderr.line! (index 0)
/// Takes Str, returns {}
extern "C" fn hosted_stderr_line(
    _ops: *const RocOps,
    _ret_ptr: *mut c_void,
    args_ptr: *const StderrLineArgs,
) {
    unsafe {
        let message = (*args_ptr).arg0.as_str();
        let _ = writeln!(io::stderr(), "{}", message);
    }
}

/// Hosted function: Stdin.line! (index 1)
/// Takes {}, returns Str
extern "C" fn hosted_stdin_line(
    ops: *const RocOps,
    ret_ptr: *mut RocStr,
    _args_ptr: *mut c_void,
) {
    let stdin = io::stdin();
    let mut line = String::new();

    match stdin.lock().read_line(&mut line) {
        Ok(_) => {
            let trimmed = line.trim_end_matches('\n').trim_end_matches('\r');
            let roc_ops = unsafe { &*ops };
            let roc_str = RocStr::from_str(trimmed, roc_ops);
            unsafe {
                *ret_ptr = roc_str;
            }
        }
        Err(_) => unsafe {
            *ret_ptr = RocStr::empty();
        },
    }
}

/// Hosted function: Stdout.line! (index 2)
/// Takes Str, returns {}
extern "C" fn hosted_stdout_line(
    _ops: *const RocOps,
    _ret_ptr: *mut c_void,
    args_ptr: *const StdoutLineArgs,
) {
    unsafe {
        let message = (*args_ptr).arg0.as_str();
        let _ = writeln!(io::stdout(), "{}", message);
    }
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
    let fns = PlatformHostedFns {
        stderr_line: hosted_stderr_line,
        stdin_line: hosted_stdin_line,
        stdout_line: hosted_stdout_line,
    };

    // Boxed so the pointer remains stable — Roc holds a reference for the duration of the call.
    let roc_ops = Box::new(make_roc_ops(core::ptr::null_mut(), hosted_functions(&fns)));

    let mut args_list = build_args_list(&roc_ops);

    let mut exit_code: i32 = -99;
    unsafe {
        roc__main_for_host(
            &*roc_ops,
            &mut exit_code as *mut i32 as *mut c_void,
            &mut args_list as *mut RocList<RocStr> as *mut c_void,
        );
    }

    exit_code
}
