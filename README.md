[![Roc-Lang][roc_badge]][roc_link]

[roc_badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Fpastebin.com%2Fraw%2FcFzuCCd7
[roc_link]: https://github.com/roc-lang/roc

# Roc platform template for Rust

A template for building [Roc platforms](https://www.roc-lang.org/platforms) using [Rust](https://www.rust-lang.org).

## Requirements

- [Rust](https://rustup.rs/) (stable)
- Python 3.12+ and authenticated [GitHub CLI](https://cli.github.com/) for verified Linux runtime downloads
- [Roc](https://www.roc-lang.org/) on `PATH`, matching the `roc` pin in the application header

## Examples


The examples use the immutable [1.1.0 release](https://github.com/lukewilliamboswell/roc-platform-template-rust/releases/tag/1.1.0). Install the compiler declared in the example header first:

```roc
app [main!] { roc: "nightly-2026-09-05-b195f5b", pf: platform "https://github.com/lukewilliamboswell/roc-platform-template-rust/releases/download/1.1.0/BqAtivonrp6omZf8pQLHed3JtdE5TuaWT3ybEgWrLDZ.tar.zst" }
```

Run an example directly: `roc examples/hello_world/main.roc`.

Each application folder contains `main.roc` and any companion modules. The header declares a compiler requirement; it does not install a compiler.

Build standalone executable: `roc build examples/hello_world/main.roc`

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

This creates a `.tar.zst` bundle containing all `.roc` files, prebuilt host libraries, verified Linux runtime files, and their license/manifest metadata. Run `./build.sh --all` first.

## Running Tests

```bash
bash ci/all_tests.sh
```

This builds the platform and runs all examples using `roc` from your local `PATH`. For the local-platform pass, the script copies the examples to a temp directory and rewrites their release bundle dependency to this checkout's `platform/main.roc`.

The script also creates a native-target platform bundle, serves it over localhost, rewrites temporary copies of the examples to use that package URL, and runs the examples again against the bundled package.

Useful focused runs:

```bash
# Test committed published dependencies from a fresh cache
RUN_PUBLIC_TESTS=1 RUN_LOCAL_TESTS=0 RUN_BUNDLE_TEST=0 bash ci/all_tests.sh

# Skip the package URL pass
RUN_BUNDLE_TEST=0 bash ci/all_tests.sh

# Test only a package URL
RUN_LOCAL_TESTS=0 PACKAGE_URL="https://github.com/lukewilliamboswell/roc-platform-template-rust/releases/download/1.1.0/BqAtivonrp6omZf8pQLHed3JtdE5TuaWT3ybEgWrLDZ.tar.zst" bash ci/all_tests.sh
```

## Supported Targets

| Target | Library |
|--------|---------|
| x64mac | `platform/targets/x64mac/libhost.a` |
| arm64mac | `platform/targets/arm64mac/libhost.a` |
| x64musl | `platform/targets/x64musl/libhost.a` |
| arm64musl | `platform/targets/arm64musl/libhost.a` |

Linux targets use an independently released runtime built from checksum-pinned Zig sources. No runtime binaries are tracked in Git. Builds verify the pinned archive’s digest and provenance/SBOM attestations before installation. See [runtime releases](runtime/README.md).

## Platform API

This platform exposes:
- `Stdout.line!` - Print a line to stdout
- `Stderr.line!` - Print a line to stderr
- `Stdin.line!` - Read a line from stdin

The main function receives command-line arguments as `List(Str)` and returns `Try({}, [Exit(I32), ..])`.

## Compiler updates and releases

`main` tracks an exact nightly in the platform and application headers.
The nightly updater advances these pins together while preserving release URLs.
CI separately checks published examples, current source, and proposed archives.
A published-example failure blocks the compiler update even if source tests pass.
Auto-merge is disabled; compiler fixes and URL updates require review.
See [nightly updates](.github/ROC_NIGHTLY.md).

Releases explicitly use the shared exact-nightly bootstrap policy on `main`;
this is not stable compiler support or an LTS promise. Package versions are
independent of compiler versions. Dispatch Release with a new unprefixed version
such as `1.1.0`. The workflow tests the proposed archive and publishes it at the
tested commit, recording its compiler requirement and checksum. Existing tags
must not be replaced. Inspect partial publications before recovering a failed run.

After publication, maintainers must test the new download from a fresh cache and
prepare complete example starters. Open a signed, validated follow-up PR updating
example URLs and README release links, preserving development compiler pins.
Starter publication and versioned documentation preservation remain manual;
the existing Pages workflow publishes only the current API documentation.
No compiler support branches or automatic backports are currently maintained.
