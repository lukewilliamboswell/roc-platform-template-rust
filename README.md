# Roc platform template for Rust

A template for building [Roc platforms](https://www.roc-lang.org/platforms) using [Rust](https://www.rust-lang.org).

## Requirements

- [Rust](https://rustup.rs/) (stable)
- [Roc](https://www.roc-lang.org/) (built from the commit pinned in `.roc-version`)

## Examples

Run examples with interpreter: `roc examples/<name>.roc`

Build standalone executable: `roc build examples/<name>.roc`

## Building

```bash
# Build for native platform only
./build.sh

# Build for all supported targets (cross-compilation)
./build.sh --all
```

## Regenerating glue

When the platform API changes (e.g. adding or modifying hosted functions in `platform/main.roc`), regenerate the Rust ABI bindings:

```bash
roc glue <path-to>/RustGlue.roc ./src/ platform/main.roc
```

This overwrites `src/roc_platform_abi.rs` with updated type definitions and dispatch tables.

## Bundling

```bash
./bundle.sh
```

This creates a `.tar.zst` bundle containing all `.roc` files and prebuilt host libraries.

## Running Tests

```bash
bash ci/all_tests.sh
```

This builds the platform and runs all examples. If `roc` is already on your PATH at the pinned commit, it will be used directly; otherwise it will be built from source.

The script also creates a native-target platform bundle, serves it over localhost, rewrites temporary copies of the examples to use the package URL, and runs the examples again against the bundled package.

Useful focused runs:

```bash
# Skip the package URL pass
RUN_BUNDLE_TEST=0 bash ci/all_tests.sh

# Test only a package URL
RUN_LOCAL_TESTS=0 PACKAGE_URL="http://localhost:8000/<bundle>.tar.zst" bash ci/all_tests.sh
```

## Supported Targets

| Target | Library |
|--------|---------|
| x64mac | `platform/targets/x64mac/libhost.a` |
| arm64mac | `platform/targets/arm64mac/libhost.a` |
| x64musl | `platform/targets/x64musl/libhost.a` |
| arm64musl | `platform/targets/arm64musl/libhost.a` |

Linux musl targets include statically linked runtime files (`crt1.o`, `libc.a`, `libunwind.a`) for standalone executables.

## Platform API

This platform exposes:
- `Stdout.line!` - Print a line to stdout
- `Stderr.line!` - Print a line to stderr
- `Stdin.line!` - Read a line from stdin

The main function receives command-line arguments as `List(Str)` and returns `Try({}, [Exit(I32)])`.
