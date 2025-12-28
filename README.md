# Roc platform template for Rust

A template for building [Roc platforms](https://www.roc-lang.org/platforms) using [Rust](https://www.rust-lang.org).

## Requirements

- [Rust](https://rustup.rs/) (stable)
- [Roc](https://www.roc-lang.org/) (built from source, see CI for pinned commit)

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

## Bundling

```bash
./bundle.sh
```

This creates a `.tar.zst` bundle containing all `.roc` files and prebuilt host libraries.

## Running Tests

```bash
bash ci/all_tests.sh
```

This builds Roc from the pinned commit, builds the platform, and runs all examples.

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
