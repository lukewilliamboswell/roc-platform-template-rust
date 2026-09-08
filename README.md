[![Roc-Lang][roc_badge]][roc_link]

[roc_badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Fpastebin.com%2Fraw%2FcFzuCCd7
[roc_link]: https://github.com/roc-lang/roc

# Roc platform template for Rust

A template for building [Roc platforms](https://www.roc-lang.org/platforms) using [Rust](https://www.rust-lang.org).

## Requirements

- [Rust](https://rustup.rs/) (stable)
- [Roc](https://www.roc-lang.org/) on `PATH`

## Examples

The examples in this repo use the latest release bundle:

```roc
app [main!] { pf: platform "https://github.com/lukewilliamboswell/roc-platform-template-rust/releases/download/1.0.0/Bu7FVf57VbTwUrUSumuTmQNMJLLmGBmer6L5AarS4qnV.tar.zst" }
```

Run examples with interpreter: `roc examples/<name>.roc`

Build standalone executable: `roc build examples/<name>.roc`

## Documentation

Platform API docs are published at <https://lukewilliamboswell.github.io/roc-platform-template-rust/>.

Generate docs locally:

```bash
roc docs platform/main.roc --output=generated-docs --no-cache
```

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

This overwrites `src/roc_platform_abi.rs` with updated type definitions and hosted symbol signatures.

## Bundling

```bash
./bundle.sh
```

This creates a `.tar.zst` bundle containing all `.roc` files and prebuilt host libraries.

## Running Tests

```bash
bash ci/all_tests.sh
```

This builds the platform and runs all examples using `roc` from your local `PATH`. For the local-platform pass, the script copies the examples to a temp directory and rewrites their release bundle dependency to this checkout's `platform/main.roc`.

The script also creates a native-target platform bundle, serves it over localhost, rewrites temporary copies of the examples to use that package URL, and runs the examples again against the bundled package.

Useful focused runs:

```bash
# Skip the package URL pass
RUN_BUNDLE_TEST=0 bash ci/all_tests.sh

# Test only a package URL
RUN_LOCAL_TESTS=0 PACKAGE_URL="https://github.com/lukewilliamboswell/roc-platform-template-rust/releases/download/0.4/3q9Kou2yUcPovfn1NhRrsvtcdfHUWmzyCaGwiupYFXUk.tar.zst" bash ci/all_tests.sh
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

The main function receives command-line arguments as `List(Str)` and returns `Try({}, [Exit(I32), ..])`.

## Independent Linux runtime releases

The [runtime producer](runtime/README.md) builds Linux startup, libc, unwinding
and Zig support libraries from checksum-pinned Zig sources. It tests both native
architectures and can publish a separate attested release with an SPDX SBOM.
