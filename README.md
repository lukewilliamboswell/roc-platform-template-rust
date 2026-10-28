# Roc platform template for Rust

Build a [Roc platform](https://www.roc-lang.org/platforms) with a Rust host for
command-line arguments, standard input, standard output and standard error.

[Manual](https://lukewilliamboswell.github.io/roc-platform-template-rust/manual/) ·
[API reference](https://lukewilliamboswell.github.io/roc-platform-template-rust/) ·
[Latest release and examples](https://github.com/lukewilliamboswell/roc-platform-template-rust/releases/latest)

Download the release's examples ZIP to start an application using that exact
platform bundle. Install a current Roc nightly, extract the archive, then run:

```sh
roc examples/hello_world/main.roc
```

For a working checkout, install Blueprint and Nix and put the latest Roc nightly
on `PATH`. Blueprint supplies the pinned repository tooling and native tools:

```sh
blueprint run build-platform
roc examples/hello_world/main.roc
blueprint run check
```

Committed examples use this checkout by relative path; release archives use an
immutable bundle URL. Native compatibility is checked on Linux x86_64, Linux
ARM64 and Apple Silicon macOS. Intel macOS is cross-compiled but unverified.

See [contributing](CONTRIBUTING.md) for changes, [security](SECURITY.md) for private
reports, and the [issue tracker](https://github.com/lukewilliamboswell/roc-platform-template-rust/issues)
for bugs and proposals.
