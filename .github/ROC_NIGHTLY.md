# Roc nightly updates

This repository checks once daily at 13:34 UTC, about four hours
after the upstream 09:00 UTC build. Late publication can wait until the next day.

The `roc` fields in `platform/main.roc` and every `examples/*/main.roc` are the compiler pins. Selected headers must agree. `.github/roc-nightly.json` selects this
repository's validation workflows, including their validation-only release paths.
The controller, its tests, and job permissions are maintained in
[roc-automation](https://github.com/lukewilliamboswell/roc-automation).
The caller workflows pin shared code to `b60d561cbd53c911b29238b30624827f8487113a`.
Dependabot proposes reviewed updates to Actions/workflow references.

Follow the shared [integration and permissions guide](https://github.com/lukewilliamboswell/roc-automation/blob/b60d561cbd53c911b29238b30624827f8487113a/docs/integration.md)
for the PR-creation setting, action allowlists, required checks, and first live
GITHUB_TOKEN run. Keep default token permissions read-only. The updater never
approves or merges PRs and receives no protection bypass.

`automation/roc-nightly` is reserved for the bot's pin-only commits. Put manual
compatibility changes on a separate branch. Candidate failures require diagnosis;
do not weaken tests or mechanically replace baselines to accept a compiler.

The PR configuration check validates the local pin and selected workflow files.
The shared repository owns the controller regression suite. Project tests remain
in this repository and run on the exact candidate commit. Scheduled bot-token
acceptance must be verified after merge; file changes alone cannot prove it.

Use the shared [OpenSSF rollout checklist](https://github.com/lukewilliamboswell/roc-automation/blob/b60d561cbd53c911b29238b30624827f8487113a/docs/openssf.md)
to record project-specific evidence. This integration does not establish badge
compliance or change repository settings.

## Repository settings and live validation

GitHub Actions may create pull requests; default workflow permissions remain
read-only. The controller never approves PRs, and `auto_merge` remains `false`.
Main requires current-commit CI checks and forbids force pushes and deletion,
including for administrators. Independent approval is not required for this
single-maintainer repository.

Dispatch Update Roc nightly on `main` to validate a candidate. Check that its
signed commit changes only compiler headers, that published-example, current-source,
and archive tests pass on all four targets, and that publication/deployment jobs
are skipped. Let the controller reconcile its reserved bot branch; keep source
fixes on separate branches.

`ci/compiler_pins.py` is vendored from the shared revision above under UPL-1.0.
Update it deliberately with the shared workflows. `ci/compiler_version.py`
validates agreement before compiler installation in each validation job.

Manual release follow-up: test the actual new URL from a fresh cache, prepare
complete pinned starters, and open a signed PR updating public URLs and release
links. Validate that PR's current SHA. Versioned documentation and starter assets
are not yet automated; the existing Pages deployment replaces the current docs.
