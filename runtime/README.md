# Independently released Linux runtime

The Linux runtime is built and versioned separately from the Rust host and Roc
compiler. Platform builds pin the released archive in `runtime/lock.json`.
macOS uses the system runtime and does not need this download for native builds.

## Inputs and contents

`source.json` pins the official Zig 0.16.0 Linux x86_64 distribution by SHA-256.
The build verifies the download before executing Zig. Zig compiles its bundled
musl, LLVM libunwind and Zig runtime sources with baseline CPU targets in empty,
separate caches for x86_64 and AArch64. We use a published Zig compiler to build
these libraries; we do not bootstrap the Zig compiler itself or fetch floating
musl/LLVM branches. The source archive URL and checksum are recorded for audit.

The archive includes five files for each Linux target:

| File | Source |
| --- | --- |
| `crt1.o` | musl startup code bundled with Zig |
| `libc.a` | musl bundled with Zig |
| `libunwind.a` | LLVM libunwind bundled with Zig |
| `libzigc.a` | Zig's libc support, including allocation functions |
| `libcompiler_rt.a` | Zig compiler runtime support |

Zig 0.16 splits some functions out of musl into its own runtime archives. Keep
these inputs explicit in the platform target declarations. The builder selects
files from Zig's final linker command: intermediate cache objects can have the
same name and must not be selected by a first-match search.

The archive also includes the exact upstream license notices and a manifest with
per-file SHA-256 digests and build inputs. The accompanying SPDX 2.3 SBOM records
the components, toolchain, source archive, and individual runtime file hashes.
Vendored musl and libunwind revisions are identified through Zig's release,
without guessing an independent upstream version from compiled archives.

## Building and testing an unpublished candidate

Requires Linux x86_64 and Python 3.12 or newer. The builder and native tests download and verify
their own pinned Zig toolchains. Native test toolchains are pinned separately in
`runtime/test-toolchains.json`.

```sh
python3 -m unittest discover -s ci -p 'test_runtime*.py' -v
python3 ci/runtime.py build
python3 ci/runtime_release.py test --target x64musl
```

`install-candidate` and `build.sh --runtime-candidate <archive>` are explicit
local/CI test operations for unpublished artifacts; they do not establish signed
provenance. Routine CI and platform publication do not use these overrides.

The runtime workflow builds once, then tests that same archive on native Linux
x86_64 and ARM64 runners. Each native job extracts the tar and compiles the reviewed smoke-test source
against those exact libraries with `-nostdlib`, exercising allocation, libc startup
and stack unwinding. No executable supplied by the build artifact is used. Platform
examples check, build, run and test against the candidate during local testing and
against the attested release during routine platform CI. The producer
workflow has no Rust or Roc compiler dependency.
Only a successful, explicitly requested `main` run may sign and publish.

## Release and adoption

Runtime versions use independent tags such as `runtime-v1.0.0`. They never become
the repository's global latest release. Changing a Roc compiler pin or the Rust
host does not rebuild or advance this runtime dependency.

1. Review source/compiler changes and run the runtime workflow with publication
   disabled. Keep writes and OIDC permissions out of build/test jobs.
2. Merge reviewed runtime changes into `main`. Dispatch
   **Linux runtime release** on the exact intended `main` commit, with a new
   version and `publish: true`.
3. The separate publication job downloads the tested artifact from that run,
   creates GitHub/Sigstore build-provenance and SPDX SBOM attestations, and releases
   the tar, checksums, SBOM, attestation bundles and proposed consumer lock. It loads only release helpers from the exact trusted `main` commit; it never
   executes build tools, downloaded scripts or smoke binaries with signing authority.
4. Verify the published bytes and attestations (the workflow performs this too).
   Review and copy `runtime-lock.proposed.json` into `runtime/lock.json` in an
   adoption PR. Verify the tag, SHA-256, and source commit against the successful
   release run. Do not resolve a floating latest version during platform builds.
5. Run normal platform CI and release-candidate tests with that lock before
   merging adoption. Future runtime updates follow the same separate release and
   reviewed lock update process.

An existing runtime tag is rejected. If publication partly succeeds, inspect the
tag, commit, archive and attestation results; preserve them and use a reviewed
recovery procedure. Do not delete/repoint tags or rebuild and replace assets.
Enable GitHub immutable releases where available as an additional repository
control; workflow checks alone cannot prevent an administrator changing assets.

## Consumer verification

Normal `build.sh` calls `python3 ci/runtime.py fetch` on Linux or for `--all`.
It requires `gh` with `gh auth login` locally, or `GH_TOKEN` in CI, plus Python.
It verifies the SHA-256 **before** verifying both attestations against:

- This exact repository and `.github/workflows/runtime-release.yml` signer.
- The reviewed source commit and `refs/heads/main` source ref.
- A GitHub-hosted runner.
- SLSA provenance v1 and SPDX SBOM predicate types.

Only then does it accept the fixed archive member list, reject links/traversal
and duplicates, check every member digest, and install files under
`platform/targets/` and `platform/runtime/`. Existing destination symlinks are
rejected. Installed files remain ignored by Git. Licenses and the runtime manifest
are included in generated platform bundles.

Attestations cryptographically sign claims about the tar's digest; there is no
long-lived repository signing key. This adds verifiable provenance and an SBOM;
it does not certify dependency safety, reproducible compilation, OpenSSF badge
compliance, or a particular SLSA level. Archive headers are normalized, but compiler
outputs may retain build paths and no bit-for-bit reproducibility claim is made.
Removing tracked binaries does not rewrite or shrink existing Git history.

The workflow delegates orchestration to `ci/runtime_release.py` (`request`,
`test`, `preflight`, `publish`, `verify`). Attestation policy is shared with the
consumer in `ci/runtime.py`; GitHub job permissions and signing actions remain
visible in the workflow.

Release preflight rejects an SBOM unless its complete document matches the
verified tar inventory and reviewed source metadata (only its validated creation
time varies). File hashes, missing/extra entries, relationships, package/source
metadata, the archive digest, and the published checksum sidecar are checked
before signing. These checks validate consistency, not arbitrary library behavior.

Runtime checks run on every PR so required-check rules cannot leave unrelated PRs
waiting for a path-filtered workflow. Publication uses the `runtime-release`
environment; its approval and branch restrictions are repository settings, not
properties that YAML alone can enforce.
