# Roc platform template for Rust

This is a template for getting started with a [roc platform](https://www.roc-lang.org/platforms) using [Rust](https://www.rust-lang.org).

If you have any ideas to improve this template, please let me know. 😀

**NOTE** the crates `roc_app` and `roc_std` have been generated using `roc glue` and [this](https://github.com/roc-lang/roc/blob/main/crates/glue/src/RustGlue.roc) build script, and will need to be re-generated once the Rust glue spec has been re-written/fixed. Currently, this is mostly helpful for the `roc_std` library which is also used within the roc compiler and should be mature.

I'm not an experienced Rust developer; any assistance with `glue.roc` spec would be most appreciated.

## Developing locally

Build the platform with `roc build.roc` to produce the prebuilt-binaries in `platform/`. 

Then you will be able to run `roc app.roc`.

## Packaging the platform

Bundle the platform source and prebuilt-binaries with `roc build --bundle .tar.br platform/main.roc`, and then upload to a URL.  

## Platform documentation

Generate the documentation with `roc docs platform/main.roc` and then serve the files in `generated-docs/` using a webserver.