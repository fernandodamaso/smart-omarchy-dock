# SmartDock GitHub Fork Migration Specification

## Objective

Turn the currently installed, non-Git SmartDock for Omarchy tree into a proper
GitHub fork of `nick-friedrich/hyprland-dock`, with a separately maintained
SmartDock release branch and an Omarchy-managed update path that pulls from the
user's fork.

## Current State

- Working plugin code: `/home/admin/.config/omarchy/plugins/admin.smartdock`
- Working plugin ID: `admin.smartdock`
- Persistent user settings: `/home/admin/.config/smartdock/dock.json`
- Enabled-plugin declaration: `/home/admin/.config/omarchy/shell.json`
- Current version: `1.1.1-custom.18`
- The installed plugin directory has no `.git` directory, so
  `omarchy plugin update admin.smartdock` cannot update it.
- The current tree passes Omarchy validation, all static checks, 34 QML tests,
  shell syntax checks, and `qmllint` with known non-fatal warnings.
- A preserved upstream checkout exists under
  `/home/admin/.local/share/smartdock-migration/20260901-135056/upstream-plugin`,
  but it is a migration archive and must remain untouched.
- The planning repository and its Git metadata now live at
  `/home/admin/Projects/smart-omarchy-dock`. It has no commits or remotes yet;
  Task 2 attaches this existing directory to the proper GitHub fork.

## Decisions

1. Create a real GitHub fork of `nick-friedrich/hyprland-dock` named
   `smart-omarchy-dock` under the account authenticated by GitHub CLI.
2. Use the existing `/home/admin/Projects/smart-omarchy-dock` planning
   repository as the canonical development checkout. Attach it to the fork
   in place instead of cloning over or nesting another repository inside it.
3. Preserve the original Git history by importing the current working tree as
   a new commit on top of the fork's upstream history. Do not construct
   artificial history for the earlier local edits.
4. Use `main` as SmartDock's stable/default branch. Keep an `upstream` remote
   pointing to `nick-friedrich/hyprland-dock`; upstream changes are imported
   only deliberately.
5. Use the globally unique plugin ID
   `io.github.${GITHUB_USER}.smartdock`, where `GITHUB_USER` is obtained from
   `gh api user --jq .login` during execution. No shell variable is committed;
   the resolved literal ID is written to the repository.
6. Start SmartDock's independent release line at `2.0.0`, replacing the local
   `1.1.1-custom.*` suffix for future releases.
7. Keep `/home/admin/.config/smartdock/dock.json` unchanged. Plugin code and
   user settings remain separate, so Git updates cannot overwrite the user's
   layout or pinned applications.
8. Install the public plugin from the fork URL with `omarchy plugin add`. The
   installed Git checkout is a deployment target and must not be edited
   directly.
9. Preserve the MIT license and original copyright notice because this is an
   explicit fork. Add SmartDock branding, documentation, and release history
   without obscuring provenance.
10. Prove the update channel with a real fast-forward from the fork after the
    Git-managed plugin has been installed.
11. Keep the prior installed tree in a timestamped, recoverable migration
    archive until the new installation and update path are verified.

## Release and Update Model

```text
/home/admin/Projects/smart-omarchy-dock
        |  commit and push
        v
GitHub fork: ${GITHUB_USER}/smart-omarchy-dock (main)
        |  omarchy plugin update
        v
~/.config/omarchy/plugins/io.github.${GITHUB_USER}.smartdock
        |
        +-- reads ~/.config/smartdock/dock.json
```

- Feature work happens on branches in the canonical development checkout.
- Stable changes are merged or fast-forwarded onto `main` and pushed to the
  fork.
- Omarchy fetches `origin HEAD` and performs a fast-forward-only update.
- Releases are tagged from validated `main`; tags document versions, while the
  Omarchy updater follows the default branch.

## Success Criteria

- GitHub reports the new repository as a fork of
  `nick-friedrich/hyprland-dock`.
- The canonical checkout has `origin` set to the SmartDock fork and `upstream`
  set to the original repository.
- `main` contains the exact current SmartDock implementation plus the new
  public metadata, migration plans, and documentation.
- The plugin validates and all existing tests pass from the canonical checkout.
- Omarchy enables `io.github.${GITHUB_USER}.smartdock` and no longer enables
  `admin.smartdock`.
- The installed plugin is a clean Git checkout whose `origin` is the SmartDock
  fork.
- The checksum of `/home/admin/.config/smartdock/dock.json` is unchanged.
- A post-install documentation commit is pulled successfully with
  `omarchy plugin update`.
- Release `v2.0.0` points to the verified commit on `main`.

## Out of Scope

- Rewriting the dock from scratch.
- Removing upstream Git history or the required MIT notice.
- Automatically merging future upstream changes.
- Publishing SmartDock to a separate plugin registry.
- Implementing the pending Dock Settings visual redesign; its plan is only
  retargeted to the new canonical source checkout.
