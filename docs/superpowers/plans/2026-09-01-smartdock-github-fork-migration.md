# SmartDock GitHub Fork Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish the current SmartDock implementation as a proper GitHub fork with its own stable branch, release identity, and verified Omarchy update channel while preserving the live user configuration.

**Architecture:** The existing planning repository at `/home/admin/Projects/smart-omarchy-dock` is attached in place to the GitHub fork and becomes the canonical source checkout; its `origin` is the user's fork and its read-only `upstream` reference is the original Hyprland Dock repository. Omarchy installs a separate Git checkout from the fork and updates it with fast-forward-only pulls, while runtime settings remain in `/home/admin/.config/smartdock/dock.json` outside both repositories.

**Tech Stack:** Git, GitHub CLI, Omarchy 4 plugin CLI, Bash, Quickshell, Qt/QML, Qt Test, Lucide SVG assets

**Spec:** `/home/admin/Projects/smart-omarchy-dock/docs/superpowers/specs/2026-09-01-smartdock-github-fork-migration.md`

## Global Constraints

- Never edit `/usr/share/omarchy`; reading its plugin commands is allowed.
- Never overwrite or delete `/home/admin/.config/smartdock/dock.json`.
- Preserve the upstream Git history, MIT license, and existing copyright notice.
- Use `/home/admin/Projects/smart-omarchy-dock` as the only development checkout after migration.
- Treat the installed Omarchy checkout as read-only deployment state.
- Resolve the GitHub login with `gh api user --jq .login`; commit the resulting literal plugin ID and URL, not shell-variable text.
- Use `main` as the fork's default and stable update branch.
- Use `2.0.0` as the first SmartDock release version.
- Do not publish a release or discard the prior installed tree until validation, installation, configuration preservation, and a real fast-forward update all pass.

---

## File Structure

### Canonical repository

- `/home/admin/Projects/smart-omarchy-dock/manifest.json` — public plugin identity and version.
- `/home/admin/Projects/smart-omarchy-dock/README.md` — fork installation, update, development, and provenance documentation.
- `/home/admin/Projects/smart-omarchy-dock/CHANGELOG.md` — independent SmartDock release history.
- `/home/admin/Projects/smart-omarchy-dock/AGENTS.md` — source-versus-installed-checkout development rules.
- `/home/admin/Projects/smart-omarchy-dock/docs/UPDATING.md` — user update and recovery instructions; also supplies the real post-install update test commit.
- `/home/admin/Projects/smart-omarchy-dock/docs/RELEASING.md` — maintainer validation and release sequence.
- All remaining plugin files — copied byte-for-byte from the frozen working snapshot before metadata edits.

### Machine state

- `/home/admin/.config/omarchy/plugins/admin.smartdock` — old non-Git installation, moved to the migration archive only after the fork is pushed and validated.
- `/home/admin/.config/omarchy/plugins/io.github.${GITHUB_USER}.smartdock` — new Git-managed installation; `${GITHUB_USER}` denotes the login resolved during execution, not a literal directory name.
- `/home/admin/.config/omarchy/shell.json` — old ID disabled and new ID enabled through Omarchy commands.
- `/home/admin/.config/smartdock/dock.json` — persistent settings; checksum must remain unchanged.
- A timestamped child of `/home/admin/.local/share/smartdock-git-migration/` — recoverable code, shell configuration, user configuration, and checksum snapshot.

---

### Task 1: Freeze and Validate the Working SmartDock Baseline

**Files:**
- Read: `/home/admin/.config/omarchy/plugins/admin.smartdock/**`
- Create: timestamped migration-directory copy `active-plugin/**`
- Create: timestamped migration-directory copy `user-config/**`
- Create: timestamped migration-directory copy `shell.json`
- Create: timestamped migration-directory checksum files
- Create: `/home/admin/.local/share/smartdock-git-migration/latest`

**Interfaces:**
- Consumes: the currently working non-Git plugin and live user configuration.
- Produces: an immutable migration input and rollback point used by every later task.

- [ ] **Step 1: Confirm the baseline is still the known working build**

Run:

```bash
cd /home/admin/.config/omarchy/plugins/admin.smartdock
test ! -d .git
test "$(jq -r '.id' manifest.json)" = "admin.smartdock"
test "$(jq -r '.version' manifest.json)" = "1.1.1-custom.18"
omarchy plugin validate .
for check_script in tests/check_*.sh; do bash "$check_script"; done
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests -import .
bash -n install.sh uninstall.sh scripts/smartdock scripts/run
```

Expected: validation and shell checks exit 0; Qt Test reports `34 passed, 0 failed`.

- [ ] **Step 2: Record the current persistent configuration checksum**

Run:

```bash
test -f /home/admin/.config/smartdock/dock.json
sha256sum /home/admin/.config/smartdock/dock.json
```

Expected: one SHA-256 line for `dock.json`; retain it in the task log for comparison.

- [ ] **Step 3: Create the recoverable migration snapshot**

Run:

```bash
MIGRATION_ROOT="/home/admin/.local/share/smartdock-git-migration/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$MIGRATION_ROOT"
cp -a /home/admin/.config/omarchy/plugins/admin.smartdock "$MIGRATION_ROOT/active-plugin"
cp -a /home/admin/.config/smartdock "$MIGRATION_ROOT/user-config"
cp -a /home/admin/.config/omarchy/shell.json "$MIGRATION_ROOT/shell.json"
(
  cd /home/admin/.config/omarchy/plugins/admin.smartdock
  find . -type f -not -path './.git/*' -print0 \
    | sort -z \
    | xargs -0 sha256sum
) > "$MIGRATION_ROOT/active-plugin.sha256"
sha256sum /home/admin/.config/smartdock/dock.json \
  > "$MIGRATION_ROOT/user-config.sha256"
printf '%s\n' "$MIGRATION_ROOT" \
  > /home/admin/.local/share/smartdock-git-migration/latest
```

Expected: `latest` contains one explicit timestamped directory and all copied files exist there.

- [ ] **Step 4: Verify the snapshot matches the live tree**

Run:

```bash
MIGRATION_ROOT="$(cat /home/admin/.local/share/smartdock-git-migration/latest)"
diff -qr \
  /home/admin/.config/omarchy/plugins/admin.smartdock \
  "$MIGRATION_ROOT/active-plugin"
sha256sum -c "$MIGRATION_ROOT/user-config.sha256"
```

Expected: `diff` prints nothing and the checksum reports `OK`.

---

### Task 2: Create the Proper GitHub Fork and Attach This Repository

**Files:**
- Modify: `/home/admin/Projects/smart-omarchy-dock/.git/config`
- Preserve: `/home/admin/Projects/smart-omarchy-dock/docs/superpowers/**`
- Read: `/home/admin/.local/share/mise/installs/gh/latest/gh_2.98.0_linux_amd64/bin/gh`

**Interfaces:**
- Consumes: GitHub authentication for the account that will own SmartDock.
- Produces: a fork recognized by GitHub, the existing planning repository attached to upstream history, `origin` for SmartDock, and `upstream` for the original project.

- [ ] **Step 1: Authenticate GitHub CLI and Git**

Run in a visible terminal so browser authentication can complete:

```bash
gh auth login --hostname github.com --web --git-protocol https
gh auth setup-git
gh auth status
GITHUB_USER="$(gh api user --jq .login)"
test -n "$GITHUB_USER"
printf 'GitHub owner: %s\n' "$GITHUB_USER"
```

Expected: GitHub reports an authenticated account and prints its login. This is an execution checkpoint; do not create or change remote repositories before it passes.

- [ ] **Step 2: Create the named fork idempotently**

Run:

```bash
GITHUB_USER="$(gh api user --jq .login)"
if gh repo view "$GITHUB_USER/smart-omarchy-dock" >/dev/null 2>&1; then
  test "$(gh api "repos/$GITHUB_USER/smart-omarchy-dock" --jq '.parent.full_name // ""')" \
    = "nick-friedrich/hyprland-dock"
else
  gh repo fork nick-friedrich/hyprland-dock \
    --fork-name smart-omarchy-dock \
    --clone=false
fi
gh api "repos/$GITHUB_USER/smart-omarchy-dock" \
  --jq '{full_name, fork, parent: .parent.full_name, default_branch}'
```

Expected: `fork` is `true` and `parent` is `nick-friedrich/hyprland-dock`. If a repository with that name exists but has a different parent, stop without changing it.

- [ ] **Step 3: Attach the existing repository to both GitHub remotes**

Run:

```bash
GITHUB_USER="$(gh api user --jq .login)"
SOURCE_REPO=/home/admin/Projects/smart-omarchy-dock
test -d "$SOURCE_REPO/.git"
test -z "$(git -C "$SOURCE_REPO" remote)"
test -z "$(git -C "$SOURCE_REPO" rev-list --all)"
git -C "$SOURCE_REPO" remote add origin \
  "https://github.com/${GITHUB_USER}/smart-omarchy-dock.git"
git -C "$SOURCE_REPO" remote add upstream \
  "https://github.com/nick-friedrich/hyprland-dock.git"
git -C "$SOURCE_REPO" fetch origin
git -C "$SOURCE_REPO" fetch upstream
git -C "$SOURCE_REPO" remote -v
```

Expected: `origin` names `${GITHUB_USER}/smart-omarchy-dock`, `upstream` names `nick-friedrich/hyprland-dock`, and both fetched `master` commits are identical.

- [ ] **Step 4: Verify ancestry and create the SmartDock release branch**

Run:

```bash
SOURCE_REPO=/home/admin/Projects/smart-omarchy-dock
test "$(git -C "$SOURCE_REPO" rev-parse origin/master)" \
  = "$(git -C "$SOURCE_REPO" rev-parse upstream/master)"
git -C "$SOURCE_REPO" switch -c main upstream/master
git -C "$SOURCE_REPO" add docs/superpowers
git -C "$SOURCE_REPO" commit -m "docs: add SmartDock migration plans"
git -C "$SOURCE_REPO" status --short --branch
```

Expected: `main` descends exactly from the upstream default-branch commit, the moved planning documents are recorded in one documentation commit, and the only remaining local-only path is the ignored `.superpowers` agent workspace.

---

### Task 3: Import the Current SmartDock Tree as an Honest Snapshot Commit

**Files:**
- Modify: `/home/admin/Projects/smart-omarchy-dock/**`
- Preserve: `/home/admin/Projects/smart-omarchy-dock/.git/**`
- Read: the timestamped migration snapshot's `active-plugin/**`

**Interfaces:**
- Consumes: the verified frozen snapshot from Task 1 and fork ancestry from Task 2.
- Produces: one commit containing the exact working SmartDock implementation on top of the original project history.

- [ ] **Step 1: Read the imported project instructions before changing files**

Run:

```bash
MIGRATION_ROOT="$(cat /home/admin/.local/share/smartdock-git-migration/latest)"
sed -n '1,220p' "$MIGRATION_ROOT/active-plugin/AGENTS.md"
```

Expected: the instructions define the QML structure, user-config boundary, validation commands, and two-space QML style.

- [ ] **Step 2: Replace the fork worktree with the frozen SmartDock snapshot**

Run:

```bash
MIGRATION_ROOT="$(cat /home/admin/.local/share/smartdock-git-migration/latest)"
SOURCE_REPO=/home/admin/Projects/smart-omarchy-dock
test -d "$SOURCE_REPO/.git"
test -f "$MIGRATION_ROOT/active-plugin/manifest.json"
rsync -a --delete \
  --exclude='.git/' \
  --exclude='docs/superpowers/' \
  "$MIGRATION_ROOT/active-plugin/" \
  "$SOURCE_REPO/"
```

Expected: the Git metadata and migration documents remain present; obsolete upstream-only files such as `scripts/hyprland-dock` are removed, and the current SmartDock assets, components, and tests appear.

- [ ] **Step 3: Prove the imported tree is byte-for-byte identical**

Run:

```bash
MIGRATION_ROOT="$(cat /home/admin/.local/share/smartdock-git-migration/latest)"
SOURCE_REPO=/home/admin/Projects/smart-omarchy-dock
diff -qr --exclude=.git --exclude=docs \
  "$MIGRATION_ROOT/active-plugin" "$SOURCE_REPO"
git -C "$SOURCE_REPO" diff --check
git -C "$SOURCE_REPO" diff --stat
```

Expected: `diff -qr` prints nothing for the plugin tree, `git diff --check` exits 0, and the stat shows the real SmartDock divergence without `.git` files or the separately committed planning documents.

- [ ] **Step 4: Validate the imported snapshot before committing it**

Run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
omarchy plugin validate .
for check_script in tests/check_*.sh; do bash "$check_script"; done
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests -import .
bash -n install.sh uninstall.sh scripts/smartdock scripts/run
/usr/lib/qt6/bin/qmllint \
  -I /usr/share/omarchy/shell \
  -I /home/admin/.cache/smartdock/qml-imports \
  Overlay.qml DockHost.qml components/Dock.qml components/DockItem.qml shell.qml
```

Expected: functional checks and Qt Test pass; `qmllint` exits 0 with only the already-known incomplete-QML-type warnings.

- [ ] **Step 5: Commit the truthful migration snapshot**

Run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
git add -A
git commit -m "feat: establish SmartDock for Omarchy"
git status --short --branch
```

Expected: one new commit descends from upstream history and the worktree is clean. Do not split the recovered local state into invented historical commits.

---

### Task 4: Establish SmartDock's Public Identity and Release Policy

**Files:**
- Modify: `/home/admin/Projects/smart-omarchy-dock/manifest.json`
- Modify: `/home/admin/Projects/smart-omarchy-dock/README.md`
- Modify: `/home/admin/Projects/smart-omarchy-dock/CHANGELOG.md`
- Modify: `/home/admin/Projects/smart-omarchy-dock/AGENTS.md`

**Interfaces:**
- Consumes: the authenticated GitHub login and imported snapshot commit.
- Produces: a concrete public plugin ID, version `2.0.0`, fork install instructions, and a stable-source workflow.

- [ ] **Step 1: Resolve and record the public identity values**

Run:

```bash
GITHUB_USER="$(gh api user --jq .login)"
SMARTDOCK_PLUGIN_ID="io.github.${GITHUB_USER}.smartdock"
SMARTDOCK_REPO_URL="https://github.com/${GITHUB_USER}/smart-omarchy-dock.git"
printf '%s\n%s\n' "$SMARTDOCK_PLUGIN_ID" "$SMARTDOCK_REPO_URL"
```

Expected: both values contain the authenticated account's literal login. These resolved values must be written literally in committed JSON and Markdown.

- [ ] **Step 2: Change the manifest to the independent release identity**

Use `apply_patch` on `manifest.json` after resolving the login:

- Replace `admin.smartdock` with the literal value printed in Step 1 for
  `SMARTDOCK_PLUGIN_ID`.
- Replace `1.1.1-custom.18` with `2.0.0`.
- Keep `SmartDock for Omarchy`, `SmartDock for Omarchy contributors`, `MIT`, the description, kinds, and entry point unchanged.

Then run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
GITHUB_USER="$(gh api user --jq .login)"
test "$(jq -r '.id' manifest.json)" = "io.github.${GITHUB_USER}.smartdock"
test "$(jq -r '.version' manifest.json)" = "2.0.0"
omarchy plugin validate .
```

Expected: the manifest contains no runtime shell-variable syntax and validation passes.

- [ ] **Step 3: Replace local-only installation and update documentation**

Use `apply_patch` on `README.md` to make these concrete changes:

- Lead with `omarchy plugin add`, followed by the literal `SMARTDOCK_REPO_URL`
  printed in Step 1 and `--enable`, as the recommended Omarchy installation.
- Document `omarchy plugin update`, followed by the literal
  `SMARTDOCK_PLUGIN_ID` printed in Step 1, as the normal update command.
- Keep standalone installation as a secondary mode and state that `smartdock update` only reinstalls from the local standalone source copy.
- Replace references to `admin.smartdock` with the resolved public ID.
- State that development happens in a separate clone and installed plugin files must not be edited.
- Add a short **Project history** section linking to `https://github.com/nick-friedrich/hyprland-dock` and explaining that SmartDock is an extensively developed MIT-licensed fork.
- Keep `/home/admin/.config/smartdock/dock.json` out of public instructions; use `~/.config/smartdock/dock.json` there.

Run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
GITHUB_USER="$(gh api user --jq .login)"
rg -n "github.com/${GITHUB_USER}/smart-omarchy-dock|io.github.${GITHUB_USER}.smartdock|Project history" README.md
! rg -n 'admin\.smartdock|1\.1\.1-custom\.18|\$\{GITHUB_USER\}' README.md manifest.json
```

Expected: the resolved repository and plugin ID appear; local IDs and unresolved variables do not.

- [ ] **Step 4: Start the independent version line and codify development boundaries**

Use `apply_patch` to:

- Add `## 2.0.0 - 2026-09-01` at the top of `CHANGELOG.md`, describing the SmartDock identity, GitHub fork distribution, public plugin ID, and preserved user configuration.
- Update `AGENTS.md` so `/home/admin/Projects/smart-omarchy-dock` is canonical source, installed Omarchy checkouts are read-only, releases come from validated `main`, and upstream merges are explicit review work.
- Preserve all earlier changelog entries as historical development records.

Run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
rg -n '^## 2\.0\.0 - 2026-09-01|canonical|read-only|upstream' CHANGELOG.md AGENTS.md
git diff --check
```

Expected: the new version is first, prior entries remain, and development policy points away from the installed checkout.

- [ ] **Step 5: Commit the public identity separately**

Run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
git add manifest.json README.md CHANGELOG.md AGENTS.md
git commit -m "chore: establish SmartDock release identity"
git status --short --branch
```

Expected: the worktree is clean and the identity commit follows the snapshot commit.

---

### Task 5: Validate and Publish the Stable `main` Branch

**Files:**
- Read: `/home/admin/Projects/smart-omarchy-dock/**`
- Update remotely: GitHub repository metadata and `main` branch

**Interfaces:**
- Consumes: the imported implementation and public identity commits.
- Produces: a validated default branch that Omarchy can clone from the user's fork.

- [ ] **Step 1: Run the complete source gate**

Run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
omarchy plugin validate .
for check_script in tests/check_*.sh; do bash "$check_script"; done
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests -import .
bash -n install.sh uninstall.sh scripts/smartdock scripts/run
/usr/lib/qt6/bin/qmllint \
  -I /usr/share/omarchy/shell \
  -I /home/admin/.cache/smartdock/qml-imports \
  Overlay.qml DockHost.qml components/Dock.qml components/DockItem.qml shell.qml
git diff --check
git status --short --branch
```

Expected: validator, all static checks, 34 QML tests, shell syntax, and lint command pass; the tree is clean.

- [ ] **Step 2: Smoke-test the standalone entry point**

Run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
set +e
timeout 8s ./scripts/run --no-color \
  > /tmp/smartdock-fork-smoke.log 2>&1
smoke_status=$?
set -e
test "$smoke_status" -eq 0 -o "$smoke_status" -eq 124
! rg -n 'ReferenceError|TypeError|QQmlApplicationEngine failed|is not installed' \
  /tmp/smartdock-fork-smoke.log
```

Expected: the dock either exits cleanly or is stopped by the timeout, and no fatal QML startup error appears.

- [ ] **Step 3: Push `main` and make it the fork's default branch**

Run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
GITHUB_USER="$(gh api user --jq .login)"
git push -u origin main
gh repo edit "$GITHUB_USER/smart-omarchy-dock" \
  --default-branch main \
  --description "A theme-aware application, window, and workspace dock for Omarchy and Hyprland" \
  --enable-issues \
  --enable-wiki=false \
  --add-topic hyprland \
  --add-topic omarchy \
  --add-topic quickshell \
  --add-topic qml \
  --add-topic dock
git push origin --delete master
```

Expected: GitHub's default branch is `main`; the obsolete fork branch `master` is removed only after the default changes. The parent repository remains available through `upstream/master` locally.

- [ ] **Step 4: Verify the remote state before touching the live installation**

Run:

```bash
GITHUB_USER="$(gh api user --jq .login)"
SOURCE_REPO=/home/admin/Projects/smart-omarchy-dock
test "$(gh api "repos/$GITHUB_USER/smart-omarchy-dock" --jq '.default_branch')" = main
test "$(gh api "repos/$GITHUB_USER/smart-omarchy-dock" --jq '.parent.full_name')" \
  = nick-friedrich/hyprland-dock
git -C "$SOURCE_REPO" fetch origin
test "$(git -C "$SOURCE_REPO" rev-parse HEAD)" \
  = "$(git -C "$SOURCE_REPO" rev-parse origin/main)"
git -C "$SOURCE_REPO" remote -v
```

Expected: local `HEAD` equals `origin/main`, GitHub still reports a proper fork, and `upstream` remains configured.

---

### Task 6: Replace the Live Non-Git Plugin with the Fork Installation

**Files:**
- Move: `/home/admin/.config/omarchy/plugins/admin.smartdock`
- Create by Omarchy: `/home/admin/.config/omarchy/plugins/io.github.${GITHUB_USER}.smartdock/**`
- Modify through Omarchy: `/home/admin/.config/omarchy/shell.json`
- Preserve unchanged: `/home/admin/.config/smartdock/dock.json`

**Interfaces:**
- Consumes: the validated public `main` branch and rollback snapshot.
- Produces: a clean, enabled Git-managed plugin whose `origin` is the user's fork.

- [ ] **Step 1: Recheck rollback data and the user-config checksum**

Run:

```bash
MIGRATION_ROOT="$(cat /home/admin/.local/share/smartdock-git-migration/latest)"
test -d "$MIGRATION_ROOT/active-plugin"
test -f "$MIGRATION_ROOT/shell.json"
sha256sum -c "$MIGRATION_ROOT/user-config.sha256"
```

Expected: all rollback inputs exist and `dock.json` reports `OK`.

- [ ] **Step 2: Disable and recoverably archive the old plugin**

Run:

```bash
MIGRATION_ROOT="$(cat /home/admin/.local/share/smartdock-git-migration/latest)"
omarchy plugin disable admin.smartdock
test -d /home/admin/.config/omarchy/plugins/admin.smartdock
mv /home/admin/.config/omarchy/plugins/admin.smartdock \
  "$MIGRATION_ROOT/retired-admin.smartdock"
omarchy-shell shell rescanPlugins
```

Expected: `admin.smartdock` no longer appears as enabled or under the active plugin directory, while the complete old tree remains recoverable in the migration archive.

- [ ] **Step 3: Install and enable the fork with Omarchy**

Run:

```bash
GITHUB_USER="$(gh api user --jq .login)"
SMARTDOCK_PLUGIN_ID="io.github.${GITHUB_USER}.smartdock"
SMARTDOCK_REPO_URL="https://github.com/${GITHUB_USER}/smart-omarchy-dock.git"
omarchy plugin add "$SMARTDOCK_REPO_URL" --enable --yes
omarchy plugin validate "/home/admin/.config/omarchy/plugins/$SMARTDOCK_PLUGIN_ID"
```

Expected: Omarchy clones the repository into the directory named by the new plugin ID, rescans it, and enables it.

- [ ] **Step 4: Verify installation identity, cleanliness, and configuration preservation**

Run:

```bash
GITHUB_USER="$(gh api user --jq .login)"
SMARTDOCK_PLUGIN_ID="io.github.${GITHUB_USER}.smartdock"
INSTALLED_PLUGIN="/home/admin/.config/omarchy/plugins/$SMARTDOCK_PLUGIN_ID"
MIGRATION_ROOT="$(cat /home/admin/.local/share/smartdock-git-migration/latest)"
test -d "$INSTALLED_PLUGIN/.git"
test "$(jq -r '.id' "$INSTALLED_PLUGIN/manifest.json")" = "$SMARTDOCK_PLUGIN_ID"
test "$(jq -r '.version' "$INSTALLED_PLUGIN/manifest.json")" = "2.0.0"
test -z "$(git -C "$INSTALLED_PLUGIN" status --porcelain)"
git -C "$INSTALLED_PLUGIN" remote get-url origin \
  | rg "github.com[:/]${GITHUB_USER}/smart-omarchy-dock(\.git)?$"
jq -e --arg old admin.smartdock --arg new "$SMARTDOCK_PLUGIN_ID" '
  ([.plugins[]?.id] | index($old)) == null and
  ([.plugins[]?.id] | index($new)) != null
' /home/admin/.config/omarchy/shell.json
sha256sum -c "$MIGRATION_ROOT/user-config.sha256"
```

Expected: the checkout is clean, origin is the fork, only the new ID is enabled, and the user configuration still reports `OK`.

- [ ] **Step 5: Restart the shell and verify the dock manually**

Run:

```bash
omarchy restart shell
omarchy plugin list --json \
  | jq --arg id "io.github.$(gh api user --jq .login).smartdock" \
      '.[] | select(.id == $id)'
```

Manually verify: one dock appears; pinned apps, current settings, window counts, Trash, workspaces, Dock Controls, settings, hover effects, and window actions still work.

Expected: the new plugin is discovered and the visible behavior matches the pre-migration dock.

- [ ] **Step 6: Keep explicit rollback commands with the migration record**

If any verification in Steps 3–5 fails, run exactly:

```bash
GITHUB_USER="$(gh api user --jq .login)"
SMARTDOCK_PLUGIN_ID="io.github.${GITHUB_USER}.smartdock"
MIGRATION_ROOT="$(cat /home/admin/.local/share/smartdock-git-migration/latest)"
omarchy plugin disable "$SMARTDOCK_PLUGIN_ID" 2>/dev/null || true
if test -d "/home/admin/.config/omarchy/plugins/$SMARTDOCK_PLUGIN_ID"; then
  mv "/home/admin/.config/omarchy/plugins/$SMARTDOCK_PLUGIN_ID" \
    "$MIGRATION_ROOT/failed-$SMARTDOCK_PLUGIN_ID"
fi
mv "$MIGRATION_ROOT/retired-admin.smartdock" \
  /home/admin/.config/omarchy/plugins/admin.smartdock
omarchy-shell shell rescanPlugins
omarchy plugin enable admin.smartdock
omarchy restart shell
```

Expected: the former plugin is restored without changing `/home/admin/.config/smartdock/dock.json`. Do not run rollback after the new installation has passed all checks.

---

### Task 7: Prove the Remote Update Channel and Publish `v2.0.0`

**Files:**
- Create: `/home/admin/Projects/smart-omarchy-dock/docs/UPDATING.md`
- Create: `/home/admin/Projects/smart-omarchy-dock/docs/RELEASING.md`
- Update remotely: `origin/main`, tag `v2.0.0`, and GitHub release `v2.0.0`
- Update through Omarchy: installed Git checkout

**Interfaces:**
- Consumes: the verified Git-managed installation from Task 6.
- Produces: a real remote commit fast-forwarded into the installed checkout and the first stable SmartDock release.

- [ ] **Step 1: Write the user update guide**

Create `docs/UPDATING.md` with these exact policies and concrete resolved IDs:

- The normal command is `omarchy plugin update` followed by the resolved
  `SMARTDOCK_PLUGIN_ID` literal from Task 4.
- Updates pull the fork's default `main` branch and preserve `~/.config/smartdock/dock.json`.
- Installed files must not be edited; contributors work in `/home/admin/Projects/smart-omarchy-dock` or their own clone.
- A fast-forward failure means the installed checkout has local changes; users should preserve any intentional edits elsewhere before reinstalling from the fork.
- `origin` is SmartDock; `upstream` is relevant only in development clones.

Use `apply_patch` and insert the authenticated login literally, then run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
GITHUB_USER="$(gh api user --jq .login)"
rg -n "omarchy plugin update io.github.${GITHUB_USER}.smartdock|main|dock.json|must not be edited" docs/UPDATING.md
! rg -n '\$\{GITHUB_USER\}|SMARTDOCK_PLUGIN_ID' docs/UPDATING.md
```

Expected: the guide is concrete and contains no unresolved identity marker.

- [ ] **Step 2: Write the maintainer release guide**

Create `docs/RELEASING.md` with this ordered release gate:

1. Work on a feature branch in the canonical source clone.
2. Update `manifest.json` and `CHANGELOG.md` together.
3. Run Omarchy validation, every `tests/check_*.sh`, Qt Test, shell syntax, `qmllint`, `git diff --check`, and the standalone smoke test.
4. Merge to `main` and push `origin main`.
5. Update one installed copy with `omarchy plugin update` and verify its clean `HEAD` equals `origin/main`.
6. Create and push an annotated version tag, then publish a GitHub release.
7. Import upstream changes only on a dedicated branch after reviewing conflicts and rerunning the complete gate.

Run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
rg -n 'manifest.json|CHANGELOG.md|qmltestrunner|qmllint|annotated|upstream' docs/RELEASING.md
git diff --check
```

Expected: the guide includes every release gate and does not instruct maintainers to edit the installed plugin.

- [ ] **Step 3: Commit and push the documentation update**

Run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
git add docs/UPDATING.md docs/RELEASING.md
git commit -m "docs: document SmartDock updates and releases"
UPDATE_COMMIT="$(git rev-parse HEAD)"
git push origin main
printf '%s\n' "$UPDATE_COMMIT" \
  > /tmp/smartdock-expected-update-commit
```

Expected: `origin/main` advances by one documentation commit after the installed clone's current commit.

- [ ] **Step 4: Pull the real update through Omarchy**

Run:

```bash
GITHUB_USER="$(gh api user --jq .login)"
SMARTDOCK_PLUGIN_ID="io.github.${GITHUB_USER}.smartdock"
INSTALLED_PLUGIN="/home/admin/.config/omarchy/plugins/$SMARTDOCK_PLUGIN_ID"
BEFORE_UPDATE="$(git -C "$INSTALLED_PLUGIN" rev-parse HEAD)"
omarchy plugin update "$SMARTDOCK_PLUGIN_ID" --yes
AFTER_UPDATE="$(git -C "$INSTALLED_PLUGIN" rev-parse HEAD)"
test "$BEFORE_UPDATE" != "$AFTER_UPDATE"
test "$AFTER_UPDATE" = "$(cat /tmp/smartdock-expected-update-commit)"
test -f "$INSTALLED_PLUGIN/docs/UPDATING.md"
test -z "$(git -C "$INSTALLED_PLUGIN" status --porcelain)"
```

Expected: Omarchy reports `Updated`, `HEAD` advances exactly to the pushed documentation commit, the guide appears, and the installed checkout remains clean.

- [ ] **Step 5: Recheck configuration and runtime after the update**

Run:

```bash
MIGRATION_ROOT="$(cat /home/admin/.local/share/smartdock-git-migration/latest)"
sha256sum -c "$MIGRATION_ROOT/user-config.sha256"
omarchy restart shell
```

Manually verify the dock appears once and retains its settings.

Expected: the user configuration is unchanged and the updated plugin works.

- [ ] **Step 6: Tag and publish the first SmartDock release**

Run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
GITHUB_USER="$(gh api user --jq .login)"
test "$(jq -r '.version' manifest.json)" = "2.0.0"
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
git tag -a v2.0.0 -m "SmartDock for Omarchy 2.0.0"
git push origin v2.0.0
gh release create v2.0.0 \
  --repo "$GITHUB_USER/smart-omarchy-dock" \
  --verify-tag \
  --title "SmartDock for Omarchy 2.0.0" \
  --generate-notes
gh release view v2.0.0 --repo "$GITHUB_USER/smart-omarchy-dock"
```

Expected: the release is published from the same commit proven through `omarchy plugin update`.

---

### Task 8: Retarget Future SmartDock Work to the Canonical Repository

**Files:**
- Modify: `/home/admin/Projects/smart-omarchy-dock/docs/superpowers/plans/2026-09-01-dock-settings-visual-redesign.md`

**Interfaces:**
- Consumes: canonical source path and version line established by Tasks 2–7.
- Produces: a settings-redesign plan that edits source, never the deployed checkout.

- [ ] **Step 1: Change the plan's implementation root**

Use `apply_patch` to replace every implementation reference to:

```text
/home/admin/.config/omarchy/plugins/admin.smartdock
```

with:

```text
/home/admin/Projects/smart-omarchy-dock
```

Also replace its global constraint permitting installed-plugin edits with the requirement that all implementation happens in the canonical source checkout and reaches the installed plugin only through Git push plus `omarchy plugin update`.

- [ ] **Step 2: Move the redesign to the independent version line**

Use `apply_patch` to replace the planned `1.1.1-custom.19` release with `2.1.0`, leaving the completed `2.0.0` fork migration release intact.

- [ ] **Step 3: Verify that no future step targets deployment state**

Run:

```bash
PLAN=/home/admin/Projects/smart-omarchy-dock/docs/superpowers/plans/2026-09-01-dock-settings-visual-redesign.md
! rg -n '/home/admin/\.config/omarchy/plugins/admin\.smartdock|1\.1\.1-custom\.19' "$PLAN"
rg -n '/home/admin/Projects/smart-omarchy-dock|2\.1\.0|omarchy plugin update' "$PLAN"
```

Expected: no development step targets the installed tree and the next feature release is `2.1.0`.

- [ ] **Step 4: Commit the local planning-document updates**

Run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
git add \
  docs/superpowers/specs/2026-09-01-smartdock-github-fork-migration.md \
  docs/superpowers/plans/2026-09-01-smartdock-github-fork-migration.md \
  docs/superpowers/plans/2026-09-01-dock-settings-visual-redesign.md
git commit -m "docs: plan SmartDock fork and source workflow"
git push origin main
git status --short --branch
```

Expected: the canonical repository records the revised migration and future work paths on `origin/main`.

---

## Final Verification Checklist

- [ ] `gh api repos/$(gh api user --jq .login)/smart-omarchy-dock --jq '.fork, .parent.full_name, .default_branch'` reports `true`, `nick-friedrich/hyprland-dock`, and `main`.
- [ ] `/home/admin/Projects/smart-omarchy-dock` is clean, `origin` is the user's fork, and `upstream` is the original repository.
- [ ] `manifest.json` contains the resolved public plugin ID and version `2.0.0`.
- [ ] `omarchy plugin validate /home/admin/Projects/smart-omarchy-dock` passes.
- [ ] Every static test and all 34 QML tests pass from the source checkout.
- [ ] The Omarchy shell enables only the public plugin ID resolved from the authenticated GitHub login.
- [ ] The installed plugin checkout has `.git`, a clean worktree, and the fork as `origin`.
- [ ] `/home/admin/.config/smartdock/dock.json` matches the pre-migration checksum.
- [ ] A real `omarchy plugin update` fast-forwards the installed clone to the documentation commit.
- [ ] GitHub release `v2.0.0` points to the verified `main` commit.
- [ ] The retired non-Git installation remains recoverable in the timestamped archive.
- [ ] The Dock Settings redesign plan targets `/home/admin/Projects/smart-omarchy-dock` and version `2.1.0`.
