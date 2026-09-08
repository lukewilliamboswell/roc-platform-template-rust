# Roc nightly updates

This repository checks once daily at 13:34 UTC, about four hours
after the upstream 09:00 UTC build. Late publication can wait until the next day.

The `roc` fields in `platform/main.roc` and every `examples/*/main.roc` are the compiler pins. Selected headers must agree; `.roc-version` is removed. `.github/roc-nightly.json` selects this
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

## Rollout still required

The [September 7 scheduled run](https://github.com/lukewilliamboswell/roc-platform-template-rust/actions/runs/34151297921)
failed at PR creation, before validation. The repository API reports
`can_approve_pull_request_reviews: false`, GitHub's combined “Allow GitHub Actions
to create and approve pull requests” setting. It was enabled on September 8,
2026 and read back as `true`, with default workflow permissions still `read`.
The controller never approves PRs; `auto_merge` remains `false`.

No repository rulesets were configured when inspected. Configure the intended
review policy and require current-commit checks before enabling automatic merging.
Verify the controller's reported statuses against a real candidate and effective
repository rules; a green dispatch alone does not prove protected merging works.

After merging, dispatch Update Roc nightly on current `main`. Verify a signed
header-only candidate, published-example and current-source jobs on all four
targets, archive tests, and skipped publication/deployment jobs. Record successful,
failed, and no-op run links in the rollout PR. Local tests do not establish live
rollout. Let the controller reconcile the reserved bot branch; keep source fixes
on separate reviewed branches.

`ci/compiler_pins.py` is vendored from the shared revision above under UPL-1.0.
Update it deliberately with the shared workflows. `ci/compiler_version.py`
validates agreement before compiler installation in each validation job.

Manual release follow-up: test the actual new URL from a fresh cache, prepare
complete pinned starters, and open a signed PR updating public URLs and release
links. Validate that PR's current SHA. Versioned documentation and starter assets
are not yet automated; the existing Pages deployment replaces the current docs.

Local validation on September 8, 2026, using `nightly-2026-09-05-b195f5b`:
all 12 examples checked, built, and ran against committed release URLs, current
source, and a native Linux x86_64 bundle. Both expect-bearing applications passed
(10 expectations per lane). The public lane used a fresh cache. Actionlint,
Bash syntax validation, and the shared configuration check passed. The other
three target platforms and a live nightly dispatch remain unverified.
