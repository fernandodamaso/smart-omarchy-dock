## Scope

- Linear issue:
- Base branch:
- Stacked parent, if any:

## Exact-SHA evidence

- Base SHA: `<40-char SHA>`
- Head SHA: `<40-char SHA>`

Any new commit invalidates acceptance evidence recorded for the previous head.

## Checks

- [ ] `Headless CI` passes for the exact head above.
- [ ] PR is **Ready for review** before merge.
- [ ] Issue-required local/physical gates are complete, or explicitly not required for this diff.
- [ ] Review conversations are resolved.
- [ ] If this is stacked work, the PR base and evidence were refreshed after the parent landed or changed.

## Local / physical evidence

Describe only gates required by the owning issue. Include sanitized results and the exact tested SHA; do not paste machine-specific secrets or unrelated environment data.

## Delivery note

Feature branches enter `main` through their PR (or a narrowly scoped recovery PR), not through a local feature-branch merge commit pushed directly to `main`.
