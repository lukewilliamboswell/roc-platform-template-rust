# Roc platform template for Rust

This is a template for getting started with a [roc platform](https://www.roc-lang.org/platforms) using [Rust](https://www.rust-lang.org).

If you have any ideas to improve this template, please let me know. 😀

## Developing locally

### Step 0. Dev environment

Dependencies:
- Nix package manager `nix develop`
- Otherwise ensure you have Roc and Cargo installed

### Step 1. Build the platform

```
$ roc build.roc
```

Build the platform with `roc build.roc` to produce the prebuilt-binaries in `platform/`.

### Step 2. Run an example

After the platform is build, you can run an example using `roc`.

```
$ roc examples/hello.roc
Roc loves Rust
```

### Step 3. Run all the tests

```
$ ROC=roc EXAMPLES_DIR=examples/ ./ci/all_tests.sh
```

## Packaging the platform

Bundle the platform first using `roc build.roc`, and then create a bundle with:

```
$ roc build --bundle .tar.br platform/main.roc
```

This will package up all the `*.roc` files a prebuilt host files `*.a` `*.rh` etc from `platform/` and give you a file like `platform/GusyN64cWI5ri8GtTv90sgKKjEtj2i8GXKaWhI0-Tk8.tar.br` which you can distribute to other users by hosting online and sharing the URL.

## Platform documentation

Generate the documentation with `roc docs platform/main.roc` and then serve the files in `generated-docs/` using a webserver.

## Advaced - LLVM IR

You can generate the LLVM IR for the app with `roc build --no-link --emit-llvm-ir examples/hello.roc` which is an authoritative reference for what roc will generate in the application object.
