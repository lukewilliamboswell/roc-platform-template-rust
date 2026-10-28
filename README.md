[![Roc-Lang][roc_badge]][roc_link]

[roc_badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Fpastebin.com%2Fraw%2FcFzuCCd7
[roc_link]: https://github.com/roc-lang/roc

# Roc platform template for Rust

A template for building [Roc platforms](https://www.roc-lang.org/platforms) using [Rust](https://www.rust-lang.org).

## Requirements

- [Rust](https://rustup.rs/) (stable)
- [Blueprint](https://github.com/lukewilliamboswell/roc-blueprint) with Nix, which provides the tooling compiler and tools
- Python 3.12+ and authenticated [GitHub CLI](https://cli.github.com/) for verified Linux linker-input downloads
- The latest [Roc](https://www.roc-lang.org/) nightly on `PATH`

## Examples

The examples in `examples/` use this checkout's platform by relative path, so
they follow the working tree and need the host built first
(`blueprint run build-platform`). Run one with
`roc examples/hello_world/main.roc`, or build a standalone executable with
`roc build examples/hello_world/main.roc`.

To use a released platform, download `roc-platform-template-rust-examples-<version>.zip`
from the [latest release](https://github.com/lukewilliamboswell/roc-platform-template-rust/releases/latest);
its examples name that release's bundle URL and carry no compiler pin.

## Documentation

Platform API docs are published at <https://lukewilliamboswell.github.io/roc-platform-template-rust/>.

Generate docs locally:

```bash
roc docs platform/main.roc --output=generated-docs --no-cache
```

## Tooling

Repository automation is written as Roc scripts in `scripts/`, run through
[Blueprint](https://github.com/lukewilliamboswell/roc-blueprint) tasks declared
in `Blueprint.roc`. Blueprint provides `roc-stable`, the pinned compiler that
runs the scripts. The platform and examples use the `roc` on your `PATH`, which
should be the latest nightly; nothing outside `scripts/` pins a compiler.

## Building

```bash
# Build for the native target only
blueprint run build-platform

# Build for all supported targets (cross-compilation)
blueprint run build-platform -- --target all
```

## Regenerating glue

When the platform API changes (e.g. adding or modifying hosted functions in `platform/main.roc`), regenerate the Rust ABI bindings:

```bash
roc glue <path-to>/RustGlue.roc ./src/ platform/main.roc
```

This overwrites `src/roc_platform_abi.rs` with updated type definitions and hosted symbol signatures.

## Bundling

```bash
blueprint run bundle -- --output-dir dist
```

This creates a `.tar.zst` bundle containing all `.roc` files, prebuilt host libraries, verified linker inputs, and their license, provenance, manifest, and SBOM metadata. Run `blueprint run build-platform -- --target all` first. `--target native` bundles only this machine's target, for local testing.

## Running Tests

```bash
blueprint run check
```

This formats and type-checks the tooling and platform, builds the native host,
and runs every example in `tests/spec.json`, comparing exact stdout, stderr and
exit codes. It then bundles the platform for the native target, serves it over
localhost with an empty package cache, and runs the examples again against the
bundle.

The examples reference the platform by relative path. Each release attaches
`roc-platform-template-rust-examples-<version>.zip`, a frozen copy that names
the release bundle, which the shared
[roc-automation](https://github.com/lukewilliamboswell/roc-automation) nightly
runs daily against the latest Roc nightly (`.github/workflows/nightly.yml`).

```bash
# Run the working-tree examples only (after building the native host)
blueprint run examples

# Run an examples archive against a bundle
blueprint run examples -- --operation test --archive <examples.zip> --bundle <bundle.tar.zst>
```

## Supported Targets

| Target | Library |
|--------|---------|
| x64mac | `platform/targets/x64mac/libhost.a` |
| arm64mac | `platform/targets/arm64mac/libhost.a` |
| x64musl | `platform/targets/x64musl/libhost.a` |
| arm64musl | `platform/targets/arm64musl/libhost.a` |

External final-link inputs have an independent signed release stream. The aggregate archive preserves the checksum-pinned Zig musl/libunwind runtime and adds project-authored macOS interfaces without copying Apple SDK files. Routine builds reuse its content-addressed cache and verify the committed size and SHA-256 on every use, so a cache hit avoids network traffic without becoming a trust decision. `libhost.a` remains current-source output. The reviewed lock pins the archive, SBOM, producer commit, and trusted publisher identity; see [linker inputs](linker-inputs/README.md).

## Platform API

This platform exposes:
- `Stdout.line!` - Print a line to stdout
- `Stderr.line!` - Print a line to stderr
- `Stdin.line!` - Read a line from stdin

The main function receives command-line arguments as `List(Str)` and returns `Try({}, [Exit(I32), ..])`.

## Compiler updates and releases

Package versions are independent of compiler versions. Dispatch Release from
`main` with a new unprefixed version such as `1.2.0`. The workflow builds every
target, bundles the platform, packages the examples archive, tests that exact
archive against that exact bundle on each target with an empty cache, and
publishes them at the tested commit with checksums and the compiler it was
tested with. Existing tags are never replaced. Committed examples are never
rewritten to release URLs.

No compiler support branches or automatic backports are currently maintained.
