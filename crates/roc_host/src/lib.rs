use core::ffi::c_void;
use roc_std::{RocList, RocStr};
use std::io::Write;
mod glue;

/// # Safety
/// TODO
#[no_mangle]
pub unsafe extern "C" fn roc_alloc(size: usize, _alignment: u32) -> *mut c_void {
    libc::malloc(size)
}

/// # Safety
/// TODO
#[no_mangle]
pub unsafe extern "C" fn roc_realloc(
    c_ptr: *mut c_void,
    new_size: usize,
    _old_size: usize,
    _alignment: u32,
) -> *mut c_void {
    libc::realloc(c_ptr, new_size)
}

/// # Safety
/// TODO
#[no_mangle]
pub unsafe extern "C" fn roc_dealloc(c_ptr: *mut c_void, _alignment: u32) {
    libc::free(c_ptr);
}

/// # Safety
/// TODO
#[no_mangle]
pub unsafe extern "C" fn roc_panic(msg: *mut RocStr, tag_id: u32) {
    match tag_id {
        0 => {
            eprintln!("Roc standard library hit a panic: {}", &*msg);
        }
        1 => {
            eprintln!("Application hit a panic: {}", &*msg);
        }
        _ => unreachable!(),
    }
    std::process::exit(1);
}

/// # Safety
/// TODO
#[no_mangle]
pub unsafe extern "C" fn roc_dbg(loc: *mut RocStr, msg: *mut RocStr, src: *mut RocStr) {
    eprintln!("[{}] {} = {}", &*loc, &*src, &*msg);
}

/// # Safety
/// TODO
#[no_mangle]
pub unsafe extern "C" fn roc_memset(dst: *mut c_void, c: i32, n: usize) -> *mut c_void {
    libc::memset(dst, c, n)
}

#[cfg(unix)]
/// # Safety
/// TODO
#[no_mangle]
pub unsafe extern "C" fn roc_getppid() -> libc::pid_t {
    libc::getppid()
}

#[cfg(unix)]
/// # Safety
/// TODO
#[no_mangle]
pub unsafe extern "C" fn roc_mmap(
    addr: *mut libc::c_void,
    len: libc::size_t,
    prot: libc::c_int,
    flags: libc::c_int,
    fd: libc::c_int,
    offset: libc::off_t,
) -> *mut libc::c_void {
    libc::mmap(addr, len, prot, flags, fd, offset)
}

#[cfg(unix)]
/// # Safety
/// TODO
#[no_mangle]
pub unsafe extern "C" fn roc_shm_open(
    name: *const libc::c_char,
    oflag: libc::c_int,
    mode: libc::mode_t,
) -> libc::c_int {
    libc::shm_open(name, oflag, mode as libc::c_uint)
}

// Protect our functions from the vicious GC.
// This is specifically a problem with static compilation and musl.
// TODO: remove all of this when we switch to effect interpreter.
pub fn init() {
    let funcs: &[*const extern "C" fn()] = &[
        roc_alloc as _,
        roc_realloc as _,
        roc_dealloc as _,
        roc_panic as _,
        roc_dbg as _,
        roc_memset as _,
        roc_fx_stdout_line as _,
    ];
    #[allow(forgetting_references)]
    std::mem::forget(std::hint::black_box(funcs));
    if cfg!(unix) {
        let unix_funcs: &[*const extern "C" fn()] =
            &[roc_getppid as _, roc_mmap as _, roc_shm_open as _];
        #[allow(forgetting_references)]
        std::mem::forget(std::hint::black_box(unix_funcs));
    }
}

#[no_mangle]
pub extern "C" fn rust_main(_args: RocList<RocStr>) -> i32 {
    // TODO
    // parse the ast here using crates from roc-lang/roc
    let roc_module_header = roc_parse::header::ModuleHeader {
        after_keyword: &[],
        params: None,
        exposes: roc_parse::ast::Collection::default(),
        interface_imports: None,
    };
    let roc_header = roc_parse::ast::Header::Module(roc_module_header);

    let ast = roc_ast::Ast {
        defs: "Some defs...".into(),
        header: roc_ast::SpacesBefore {
            before: RocList::from_slice(&[roc_ast::CommentOrNewline {
                str: "Some comment...".into(),
                tag: roc_ast::CommentOrNewlineTag::DocComment,
            }]),
            item: roc_header.into(),
        },
    };

    extern "C" {
        #[link_name = "roc__main_for_host_1_exposed"]
        pub fn caller(ast: *const roc_ast::Ast) -> i32;

        #[link_name = "roc__main_for_host_1_exposed_size"]
        pub fn size() -> i64;
    }

    init();

    unsafe {
        let result = caller(&ast);

        // roc now owns ast and will cleanup, so we forget them here
        // to prevent rust from dropping.
        std::mem::forget(ast);

        debug_assert_eq!(std::mem::size_of_val(&result) as i64, size());

        result
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_log(line: &RocStr) {
    let stdout = std::io::stdout();

    let mut handle = stdout.lock();

    handle
        .write_all(line.as_bytes())
        .and_then(|()| handle.write_all("\n".as_bytes()))
        .and_then(|()| handle.flush())
        .unwrap();
}

#[no_mangle]
pub extern "C" fn roc_fx_stdout_line(line: &RocStr) -> roc_std::RocResult<(), glue::IOErr> {
    let stdout = std::io::stdout();

    let mut handle = stdout.lock();

    handle
        .write_all(line.as_bytes())
        .and_then(|()| handle.write_all("\n".as_bytes()))
        .and_then(|()| handle.flush())
        .map_err(|io_err| io_err.into())
        .into()
}
