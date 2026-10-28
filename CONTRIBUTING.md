# Contributing

Use [issues](https://github.com/lukewilliamboswell/roc-platform-template-rust/issues) for bug reports, feature requests and design discussion. Include your platform release, Roc compiler version, operating system and a small reproduction for a bug. Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

Read the [contributor guide](https://lukewilliamboswell.github.io/roc-platform-template-rust/manual/contributing.html#contribute), or the [manual sources](docs/index.adoc), for environment setup, testing and release procedures.

Create a branch from the latest `main` and open a pull request explaining the affected behavior, the change and its validation. Keep commits focused and sign them (`git commit -S`). Add tests for significant new behavior and regressions, and update the documentation when public behavior changes.

Run `blueprint run check` before submitting. Pull requests must pass both `CI required` and `Release required`; the release workflow performs a dry run against the proposed source. Keep examples pointed at the working-tree platform so tests exercise your changes.

Preserve merge history for changes that publish linker inputs: the producer's source commit and the signed lock commit are part of the release evidence and must not be squashed. Published release tags and assets are immutable; fixes use a new release version.
