# Independently released Linux linker inputs

The Linux startup, libc, unwinding, and compiler-runtime files are linker inputs,
not Rust host outputs. They therefore have an independent release cycle selected
by `runtime/link-inputs.lock.json`. `libhost.a` remains part of the platform host
cycle: changing host source can require a new host without rebuilding stable
operating-system inputs.

This separation matters because ordinary pull requests should validate the code
under review, not repeatedly download Zig and reconstruct an already reviewed
dependency. Each locked target archive has an immutable release name, byte size,
and SHA-256. CI restores archives from GitHub Actions cache by lock identity and
rehashes every cache hit. A cache miss downloads only the selected release asset.
The lock authorizes bytes; the cache merely avoids network traffic.

## Contents and producer identity

`source.json` pins the Zig 0.16.0 distribution and source archive by SHA-256. The
producer builds `x64musl` and `arm64musl` in separate empty caches and selects the
five files from Zig's final link command: `crt1.o`, `libc.a`, `libunwind.a`,
`libzigc.a`, and `libcompiler_rt.a`. Each target archive also contains licenses
and an inner manifest with per-file hashes.

The producer fingerprint covers the builder, native validator, source and test
toolchain pins, smoke source, and workflow. This makes a material producer change
fail as stale instead of silently substituting newly built bytes during routine
CI. Archive hashes identify the exact consumer bytes; the fingerprint answers
whether their recipe is still current. These are related but distinct checks.

## Producing and publishing a change

The unprivileged `runtime-release.yml` workflow is dispatch-only. It builds both
targets, tests each archive on its native architecture, emits canonical
`build-input-release.json`, and attests that manifest and both archives. It has no
repository or release write authority.

Use this order when the producer fingerprint changes:

1. Stage the material change in a same-repository PR. Ordinary validation may
   report a stale lock until the new release is adopted.
2. Optionally dispatch `runtime-release.yml` on the PR branch with
   `release_candidate=true` and `expected_sha` set to its exact head. Review the
   native tests, manifest, archive hashes, and attestations. This unprivileged
   preview creates no release and changes no lock.
3. From `main`, dispatch **Publish linker inputs** (`publish-linker-inputs.yml`)
   with `pull-request` set to that PR number. Its full-SHA-pinned trusted wrapper
   reruns the producer at the exact PR head, verifies workflow and source
   identity, hashes, target inventory, and attestations, publishes an immutable
   manifest-hash-derived release, and appends a lease-guarded, GitHub-signed
   `runtime/link-inputs.lock.json`-only commit to the PR.
4. Review the lock as a dependency update and rerun routine CI against the
   released bytes. Merge with a merge commit after all required checks pass.
   Build and publish the Roc platform bundle later through its separate release
   workflow, using the adopted lock.

The optional preview does not replace the publisher's own producer run.

The split authority is intentional: PR code may compile, but cannot publish or
write its own asserted lock; trusted default-branch code may publish inert tested
bytes, but never executes scripts from the candidate artifact. Keeping the
PR-built release after merge preserves the exact source-to-tests-to-attestation
chain. Do not rebuild or promote it on `main`.

The merge commit keeps both the attested producer commit and signed lock-only
commit visible. Changed candidate bytes require a new content identity; never
replace a published asset or move its tag.

## Routine consumption

`build.sh` requests only the native target unless `--all` is used. The consumer:

1. recomputes the producer fingerprint;
2. locates the target archive in the local content cache;
3. downloads the exact locked release asset only on a miss;
4. checks size and SHA-256 even for a cache hit;
5. rejects links, traversal, duplicates, unexpected files, and inner hash errors;
6. installs through the declared `platform/targets/` and metadata paths.

Routine builds do not query attestations. Attestations are admission evidence
checked by the trusted publisher; the committed content hashes provide cheap,
offline integrity checks on every use. This avoids turning GitHub's attestation
service into a routine availability dependency while retaining provenance at the
release boundary.

During the first migration only, absence of `runtime/link-inputs.lock.json` reads
the existing attested `runtime/lock.json`; it never rebuilds. Remove that legacy
lock and bootstrap branch after the publisher adds the first signed content lock.
The trusted wrapper must already exist on the default branch, so land the producer,
consumer, wrapper, and fallback as an infrastructure PR first. Then open a
same-repository adoption PR that removes the legacy fallback and old lock, dispatch
the default-branch publisher for that PR, and let its signed lock-only commit make
the adoption PR green. This one-time ordering constraint does not recur after the
content lock exists.
