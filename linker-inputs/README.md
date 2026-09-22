# Independently released linker inputs

All external final-link inputs have one release cycle, independent of the Rust
host and Roc platform release. `libhost.a` is deliberately excluded and is
always rebuilt from the current checkout.

`scripts/linker_inputs.py fetch` downloads the exact archive pinned by
`linker-inputs.lock.json`, checks its SHA-256 and size, verifies provenance and
SPDX attestations against the pinned repository, workflow and source commit,
then validates every archive member. `stage` performs the same checks for a
local candidate and installs into a fresh staging tree (or `platform` by
default). `check` is non-mutating.

The macOS interfaces are generated solely from the reviewed catalog in this
directory. The generator never reads SDK/system `.tbd` files. The archive also
contains the catalog, its provenance, full Linux licenses, a dependency
manifest and an SPDX inventory.

Release tags are `linker-inputs-vX.Y.Z`. After merging, dispatch
`.github/workflows/linker-inputs.yml`; publish only from the repository default
branch. Adopt the emitted proposed lock in a separate reviewed change.
