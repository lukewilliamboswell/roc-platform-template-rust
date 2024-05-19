use core::ffi::c_void;
use roc_std::RocStr;
use std::io::Write;

extern "C" {
    #[link_name = "roc__mainForHost_1_exposed_generic"]
    pub fn roc_main(output: *mut u8);

    #[link_name = "roc__mainForHost_1_exposed_size"]
    pub fn roc_main_size() -> i64;

    #[link_name = "roc__mainForHost_0_caller"]
    fn call_Fx(flags: *const u8, closure_data: *const u8, output: *mut roc_std::RocResult<(), i32>);

    #[allow(dead_code)]
    #[link_name = "roc__mainForHost_0_size"]
    fn size_Fx() -> i64;

    #[allow(dead_code)]
    #[link_name = "roc__mainForHost_0_result_size"]
    fn size_Fx_result() -> i64;
}

#[no_mangle]
pub unsafe extern "C" fn roc_alloc(size: usize, _alignment: u32) -> *mut c_void {
    return libc::malloc(size);
}

#[no_mangle]
pub unsafe extern "C" fn roc_realloc(
    c_ptr: *mut c_void,
    new_size: usize,
    _old_size: usize,
    _alignment: u32,
) -> *mut c_void {
    return libc::realloc(c_ptr, new_size);
}

#[no_mangle]
pub unsafe extern "C" fn roc_dealloc(c_ptr: *mut c_void, _alignment: u32) {
    return libc::free(c_ptr);
}

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

#[no_mangle]
pub unsafe extern "C" fn roc_dbg(loc: *mut RocStr, msg: *mut RocStr, src: *mut RocStr) {
    eprintln!("[{}] {} = {}", &*loc, &*src, &*msg);
}

#[no_mangle]
pub unsafe extern "C" fn roc_memset(dst: *mut c_void, c: i32, n: usize) -> *mut c_void {
    libc::memset(dst, c, n)
}

#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn roc_getppid() -> libc::pid_t {
    libc::getppid()
}

#[cfg(unix)]
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
        roc_fx_stdoutLine as _,
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
pub extern "C" fn rust_main() -> i32 {
    init();
    let size = unsafe { roc_main_size() } as usize;
    let layout = core::alloc::Layout::array::<u8>(size).unwrap();

    unsafe {
        let buffer = std::alloc::alloc(layout);

        roc_main(buffer);

        let out = call_the_closure(buffer);

        std::alloc::dealloc(buffer, layout);

        return out;
    }
}

pub unsafe fn call_the_closure(closure_data_ptr: *const u8) -> i32 {
    // Main always returns an i32. just allocate for that.
    let mut out: roc_std::RocResult<(), i32> = roc_std::RocResult::ok(());

    call_Fx(
        // This flags pointer will never get dereferenced
        core::mem::MaybeUninit::uninit().as_ptr(),
        closure_data_ptr as *const u8,
        &mut out,
    );

    match out.into() {
        Ok(()) => 0,
        Err(exit_code) => exit_code,
    }
}

/// See docs in `platform/Stdout.roc` for descriptions
///
/// Note it would be preferable to generate the implementation for a tag union in Roc
/// using `roc glue` and then use that here, however there is at least one bug with the current
/// RustGlue.roc spec that needs investigation. For now we use a RocStr as a workaround and a
/// much simpler interface between roc and the host.
fn handle_stdout_err(io_err: std::io::Error) -> RocStr {
    match io_err.kind() {
        std::io::ErrorKind::BrokenPipe => RocStr::from("ErrorKind::BrokenPipe"),
        std::io::ErrorKind::WouldBlock => RocStr::from("ErrorKind::WouldBlock"),
        std::io::ErrorKind::WriteZero => RocStr::from("ErrorKind::WriteZero"),
        std::io::ErrorKind::Unsupported => RocStr::from("ErrorKind::Unsupported"),
        std::io::ErrorKind::Interrupted => RocStr::from("ErrorKind::Interrupted"),
        std::io::ErrorKind::OutOfMemory => RocStr::from("ErrorKind::OutOfMemory"),
        _ => RocStr::from(RocStr::from(format!("{:?}", io_err).as_str())),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_stdoutLine(line: &RocStr) -> roc_std::RocResult<(), RocStr> {
    let stdout = std::io::stdout();

    let mut handle = stdout.lock();

    handle
        .write_all(line.as_bytes())
        .and_then(|()| handle.write_all("\n".as_bytes()))
        .and_then(|()| handle.flush())
        .map_err(handle_stdout_err)
        .into()
}
