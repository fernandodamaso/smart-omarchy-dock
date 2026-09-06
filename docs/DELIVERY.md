# Delivery and review gates

This document is the delivery contract for SmartDock changes. It complements the local validation matrix in `AGENTS.md`; it does not replace physical Omarchy/Hyprland qualification where an issue requires it.

## Pull-request path to `main`

1. Feature work enters `main` through a pull request. Do not locally merge a feature branch into `main` and push the result.
2. Keep the pull request Draft while implementation or required evidence is incomplete. Transition it to **Ready for review** only when the exact current head is the candidate being accepted.
3. The required GitHub check is `Headless CI`. It runs against the exact checked-out PR head and records both base and head SHAs in the workflow summary.
4. Record the exact base and head SHAs in the PR evidence. Any new commit invalidates prior acceptance evidence for the old head.
5. Physical Omarchy evidence is required only when the owning issue calls for it. CI/docs/governance-only changes do not automatically repeat the full physical matrix.
6. Emergency recovery work still uses a narrowly scoped recovery PR. Do not bypass the PR path with a local feature-branch merge commit.

## Exact-SHA evidence

Before accepting a PR, record:

```text
base: <40-character base commit SHA>
head: <40-character PR-head commit SHA>
```

The GitHub Actions run records the same pair in its job summary. For local evidence, obtain them with:

```bash
git rev-parse origin/<base-branch>
git rev-parse HEAD
```

Evidence applies only to that pair. Rebase, amend, merge, cherry-pick, or any other new commit means the previous head evidence is stale and must not be reused.

## Headless CI scope

GitHub-hosted Ubuntu runners execute only checks that are meaningful without Omarchy, Hyprland, or a running Quickshell session:

- shell syntax for repository shell entry points and structural test scripts;
- repository structural guards in `tests/check_*.sh`;
- JavaScript model tests in `tests/test_*.mjs`;
- Python model tests in `tests/test_*.py`;
- pure Qt/QML tests via `qmltestrunner`;
- `git diff --check` for the PR/base diff.

The following remain local/physical gates because a stock GitHub runner does not provide the real host environment: standalone Quickshell smoke tests, `omarchy plugin validate .`, Omarchy-shell-aware `qmllint`, Hyprland interaction, live plugin reload, screen/hotplug behavior, and other issue-specific physical acceptance.

## Stacked branches

When a branch depends on another unmerged branch:

1. Create the child from the parent branch's exact head.
2. Open the child PR against the parent branch so the diff shows only child work.
3. Record the parent head as the child's tested base SHA.
4. Do not treat child evidence as valid after the parent branch changes.
5. After the parent lands, retarget the child PR to `main` and rebase or rebuild the child on the new `main` tip. Prefer a clean replay/cherry-pick when the old stack contains unrelated merge history.
6. Rerun `Headless CI` and any issue-required local gates on the new head/base pair before review or merge.

A stacked branch must never be merged into `main` merely because an earlier parent SHA was accepted.

## Main protection policy

Activate protection only after this workflow has landed on `main` and a post-merge `Headless CI` sanity run succeeds.

Recommended `main` settings:

- require a pull request before merging;
- require `Headless CI` to pass;
- require the branch to be up to date before merge so the accepted base is current;
- require conversation resolution;
- block force pushes and branch deletion;
- do not permit ordinary direct pushes to bypass the PR path.

### Approval-count constraint

Do **not** blindly require one non-author approval in a repository where the only trusted maintainer is also the PR author. GitHub does not let an author satisfy their own required approval, so an approval count of `1` can make every PR permanently unmergeable.

For an effectively solo-maintained repository, use the CI/PR/up-to-date/conversation gates above with required approvals set to `0` until a second trusted reviewer is confirmed. Once a second reviewer with appropriate repository access exists, raise required approvals to `1`.

FDM-841's current acceptance criterion of "a PR without an approval cannot merge" therefore cannot be safely enforced unless that second reviewer exists. Keep that constraint explicit rather than creating a ruleset that locks the maintainer out.

## FDM-841 activation order

1. Keep the FDM-841 PR Draft while FDM-840 qualifies the current `main` baseline.
2. After FDM-840 completes, refresh/rebase FDM-841 if `main` moved and rerun `Headless CI` on the new exact SHA pair.
3. Merge FDM-841 through the PR.
4. Run one post-merge `Headless CI` sanity check on `main`.
5. Enable the `main` protection settings above, choosing approval count `0` or `1` according to the reviewer constraint.
