use std::ffi::{c_char, CString};

fn main() {
    // Rust's own startup provides std::env::args(); hand it to the host as C argv.
    let args: Vec<CString> = std::env::args()
        .map(|arg| CString::new(arg).unwrap_or_default())
        .collect();
    let argv: Vec<*const c_char> = args.iter().map(|arg| arg.as_ptr()).collect();
    std::process::exit(host::rust_main(argv.len() as i32, argv.as_ptr()));
}
