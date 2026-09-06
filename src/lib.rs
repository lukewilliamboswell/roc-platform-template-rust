//! Roc platform host implementation for Roc's symbol-based host ABI.
//!
//! This host provides memory management and I/O effects for Roc programs.

use std::ffi::c_void;
use std::io::{self, BufRead, Write};
use std::mem::ManuallyDrop;

mod roc_platform_abi;

use crate::roc_platform_abi::{
    make_roc_host, roc_main, DefaultAllocators, DefaultHandlers, HostStderrLineResult,
    HostStderrLineResultPayload, HostStderrLineResultTag, HostStdinLineResult,
    HostStdinLineResultPayload, HostStdinLineResultTag, HostStdoutLineResult,
    HostStdoutLineResultPayload, HostStdoutLineResultTag, RocHost, RocList, RocStr,
};

/// Flush generated instructions from the AArch64 caches.
///
/// TODO: Remove this compatibility symbol once Roc ships the upstream fix.
/// Tracking: https://github.com/lukewilliamboswell/roc-platform-template-rust/issues/11
/// Upstream: https://github.com/roc-lang/roc/issues/11161
#[cfg(all(target_os = "linux", target_arch = "aarch64"))]
#[no_mangle]
pub unsafe extern "C" fn __clear_cache(begin: *mut c_void, end: *mut c_void) {
    use core::arch::asm;

    let begin = begin as usize;
    let end = end as usize;
    let cache_type: usize;

    asm!(
        "mrs {cache_type}, ctr_el0",
        cache_type = out(reg) cache_type,
        options(nomem, nostack, preserves_flags),
    );

    // IDC means instruction-to-data cache coherency does not require explicit
    // data-cache cleaning to the point of unification.
    if cache_type & (1 << 28) == 0 {
        let data_cache_line_size = 4 << ((cache_type >> 16) & 0xf);
        let mut address = begin & !(data_cache_line_size - 1);

        while address < end {
            asm!(
                "dc cvau, {address}",
                address = in(reg) address,
                options(nostack, preserves_flags),
            );
            address += data_cache_line_size;
        }
    }

    asm!("dsb ish", options(nostack, preserves_flags));

    // DIC means data-to-instruction cache coherency does not require explicit
    // instruction-cache invalidation to the point of unification.
    if cache_type & (1 << 29) == 0 {
        let instruction_cache_line_size = 4 << (cache_type & 0xf);
        let mut address = begin & !(instruction_cache_line_size - 1);

        while address < end {
            asm!(
                "ic ivau, {address}",
                address = in(reg) address,
                options(nostack, preserves_flags),
            );
            address += instruction_cache_line_size;
        }
    }

    asm!("dsb ish", "isb", options(nostack, preserves_flags));
}

static mut ROC_HOST: *mut RocHost = core::ptr::null_mut();

fn set_roc_host(roc_host: *mut RocHost) {
    unsafe {
        ROC_HOST = roc_host;
    }
}

fn roc_host_ptr() -> *mut RocHost {
    unsafe {
        if ROC_HOST.is_null() {
            eprintln!("roc host error: RocHost not initialized");
            std::process::exit(1);
        }
        ROC_HOST
    }
}

fn roc_host() -> &'static RocHost {
    unsafe { &*roc_host_ptr() }
}

fn stderr_line_ok() -> HostStderrLineResult {
    HostStderrLineResult {
        payload: HostStderrLineResultPayload {
            ok: ManuallyDrop::new(()),
        },
        tag: HostStderrLineResultTag::Ok,
    }
}

fn stderr_line_err(err: impl std::fmt::Display) -> HostStderrLineResult {
    HostStderrLineResult {
        payload: HostStderrLineResultPayload {
            err: ManuallyDrop::new(RocStr::from_str(&err.to_string(), roc_host())),
        },
        tag: HostStderrLineResultTag::Err,
    }
}

fn stdin_line_ok(line: RocStr) -> HostStdinLineResult {
    HostStdinLineResult {
        payload: HostStdinLineResultPayload {
            ok: ManuallyDrop::new(line),
        },
        tag: HostStdinLineResultTag::Ok,
    }
}

fn stdin_line_err(err: impl std::fmt::Display) -> HostStdinLineResult {
    HostStdinLineResult {
        payload: HostStdinLineResultPayload {
            err: ManuallyDrop::new(RocStr::from_str(&err.to_string(), roc_host())),
        },
        tag: HostStdinLineResultTag::Err,
    }
}

fn stdout_line_ok() -> HostStdoutLineResult {
    HostStdoutLineResult {
        payload: HostStdoutLineResultPayload {
            ok: ManuallyDrop::new(()),
        },
        tag: HostStdoutLineResultTag::Ok,
    }
}

fn stdout_line_err(err: impl std::fmt::Display) -> HostStdoutLineResult {
    HostStdoutLineResult {
        payload: HostStdoutLineResultPayload {
            err: ManuallyDrop::new(RocStr::from_str(&err.to_string(), roc_host())),
        },
        tag: HostStdoutLineResultTag::Err,
    }
}

/// Hosted function: Host.stderr_line!
#[no_mangle]
pub extern "C" fn roc_stderr_line(message: RocStr) -> HostStderrLineResult {
    let result = writeln!(io::stderr(), "{}", message.as_str());
    message.decref(roc_host());

    match result {
        Ok(()) => stderr_line_ok(),
        Err(err) => stderr_line_err(err),
    }
}

/// Hosted function: Host.stdin_line!
#[no_mangle]
pub extern "C" fn roc_stdin_line() -> HostStdinLineResult {
    let stdin = io::stdin();
    let mut line = String::new();

    match stdin.lock().read_line(&mut line) {
        Ok(_) => {
            let trimmed = line.trim_end_matches('\n').trim_end_matches('\r');
            stdin_line_ok(RocStr::from_str(trimmed, roc_host()))
        }
        Err(err) => stdin_line_err(err),
    }
}

/// Hosted function: Host.stdout_line!
#[no_mangle]
pub extern "C" fn roc_stdout_line(message: RocStr) -> HostStdoutLineResult {
    let result = writeln!(io::stdout(), "{}", message.as_str());
    message.decref(roc_host());

    match result {
        Ok(()) => stdout_line_ok(),
        Err(err) => stdout_line_err(err),
    }
}

#[no_mangle]
pub extern "C" fn roc_alloc(length: usize, alignment: usize) -> *mut c_void {
    DefaultAllocators::roc_alloc(roc_host_ptr(), length, alignment)
}

#[no_mangle]
pub extern "C" fn roc_dealloc(ptr: *mut c_void, alignment: usize) {
    DefaultAllocators::roc_dealloc(roc_host_ptr(), ptr, alignment);
}

#[no_mangle]
pub extern "C" fn roc_realloc(
    ptr: *mut c_void,
    new_length: usize,
    alignment: usize,
) -> *mut c_void {
    DefaultAllocators::roc_realloc(roc_host_ptr(), ptr, new_length, alignment)
}

#[no_mangle]
pub extern "C" fn roc_dbg(bytes: *const u8, len: usize) {
    DefaultHandlers::roc_dbg(roc_host_ptr(), bytes, len);
}

#[no_mangle]
pub extern "C" fn roc_expect_failed(bytes: *const u8, len: usize) {
    DefaultHandlers::roc_expect_failed(roc_host_ptr(), bytes, len);
}

#[no_mangle]
pub extern "C" fn roc_crashed(bytes: *const u8, len: usize) {
    DefaultHandlers::roc_crashed(roc_host_ptr(), bytes, len);
}

/// Build a RocList<RocStr> from command-line arguments.
fn build_args_list(roc_host: &RocHost) -> RocList<RocStr> {
    let args: Vec<String> = std::env::args().collect();

    if args.is_empty() {
        return RocList::empty();
    }

    let list = RocList::<RocStr>::allocate(args.len(), roc_host);
    let elements = list.elements;
    for (i, arg) in args.iter().enumerate() {
        let roc_str = RocStr::from_str(arg, roc_host);
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
    let mut roc_host = make_roc_host(core::ptr::null_mut());
    set_roc_host(&mut roc_host);

    let args_list = build_args_list(&roc_host);

    let exit_code = unsafe { roc_main(args_list) };
    set_roc_host(core::ptr::null_mut());
    exit_code
}
