# Automation adoption evidence

This record accompanies PR #81 and tracking issue #64. It identifies exercised
controls, not a claim of complete project security or dependency coverage.

## Native-input admission

- Producer source: `ca25d44325f0d6fd535592bb7717bfdbcf7de36a`.
- [Native producer and both architecture tests](https://github.com/lukewilliamboswell/roc-platform-template-rust/actions/runs/40779341689) passed before attestation.
- [Trusted publisher](https://github.com/lukewilliamboswell/roc-platform-template-rust/actions/runs/40779323870) verified the candidate and transferred the immutable assets.
- [Adopted release](https://github.com/lukewilliamboswell/roc-platform-template-rust/releases/tag/linker-inputs-sha256-ee606310ae32faf75c8fb1be644ec56526d7a9edb8d7591c39251e630f4155d9).
- Signed lock-only commit: `d61f30a18810f5b02dec528e34eb73eceb5289cd` (GitHub verification: valid).
- Two isolated local producer builds yielded byte-identical archives. Routine use
  checks the lock fingerprint, archive size/hash, member inventory and member hashes.

The commits following the lock contain no producer-input changes. This evidence
commit also triggers ordinary PR validation after the token-generated lock commit;
pre-adoption workflow runs do not establish that the new lock works.

## Validation

Local source-policy, formatting and unit checks passed with tooling compiler
`nightly-2026-10-25-72704da`; product examples passed against
`nightly-2026-10-28-bad769b`. The independent runtime suite has 33 tests, the
example-driver suite has three cases including a deadline, and release-evidence
checks exercise all four subjects plus tampered hashes, sidecars and inventories.

The current [PR checks](https://github.com/lukewilliamboswell/roc-platform-template-rust/pull/81/checks)
are the authority for the final tested head. Both `CI required` and
`Release required` must pass before merge. The settings checker must pass after
SECURITY.md reaches main; before merge its default-branch file check is expected
to report that single missing file.

## Explicit follow-ups

- [Intel macOS native coverage: roc-automation #101](https://github.com/lukewilliamboswell/roc-automation/issues/101): cross-compiled bytes are retained, but no native compatibility claim is made.
- [Linker-input SBOM publication and independent admission: roc-automation #62](https://github.com/lukewilliamboswell/roc-automation/issues/62): supplier documents are unavailable and coverage remains explicitly incomplete.
- [Shared platform release adapter: roc-automation #100](https://github.com/lukewilliamboswell/roc-automation/issues/100): retain the local adapter until the released shared utility supports platforms.

Product release 1.2.0 and its assets are unchanged. This PR does not publish 1.2.1.
