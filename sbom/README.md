# Product release SBOMs

`blueprint run prepare-sbom -- --release-version VERSION --bundle FILENAME --output-dir dist`
uses the reviewed Blueprint 0.8.0 SBOM executable to inspect the resolved
Blueprint specification and lock, bind SPDX 3.0.1 and CycloneDX 1.7 documents to
each final deliverable, and check the documents against their inventory and
actual subject bytes. The generated inventories, sidecar manifests and evidence
are retained as release assets. Tooling is a build dependency; it is never
reported as shipped merely because Blueprint provisions it.

The platform archive is a `source` subject containing independently identified
native members for all four targets. Native member SHA-256 values describe the
member bytes; the subject SHA-256 describes the enclosing archive. Rust standard
library and Linux runtime composition is recorded separately from build tools.
Cargo.lock currently resolves no external crates. This does not imply that the
Rust standard library contains no third-party code. Coverage findings state the
remaining uncertainty explicitly.

Examples, API documentation and manual subjects use separate compositions. ZIP
members are checked against the files actually packaged; the `.tar.zst` member
listing interface is used only for the platform bundle. A source target is
intentional for each distributable archive and document, regardless of the
builder's architecture.

`inputs.json` records one reviewed disposition for every Blueprint input. Adding
or removing a tool, task or locked program requires reviewing this file;
`blueprint-sbom inspect` fails on missing or stale dispositions.

## Coverage and corrections

Local generation and consistency checks do not authenticate supplier provenance
or establish complete dependency coverage. Missing supplier SBOMs remain explicit
findings in the released inventories; never disguise sidecars as target archives.
Corrections to a published inventory need a new immutable document revision bound
to the software digest. Changed software bytes need a new software version.
