# Updating SmartDock

SmartDock is installed as a Git-managed Omarchy plugin from the SmartDock
fork. Run the normal update command with the public plugin ID:

```bash
omarchy plugin update io.github.fernandodamaso.smartdock --yes
```

Updates pull the fork's default `main` branch. They preserve the user's
settings in `~/.config/smartdock/dock.json`; plugin updates do not replace or
reset that file.

Installed plugin files are deployment state and must not be edited directly.
Contributors should work in `/home/admin/Projects/smart-omarchy-dock` or in
their own development clone, then push changes and update the installed copy
through Omarchy.

## Fast-forward failures

Omarchy updates the installed checkout with a fast-forward-only pull. A
fast-forward failure means that the installed checkout has local changes or
otherwise no longer follows the fork's history. Preserve any intentional
edits elsewhere before reinstalling the plugin from the fork; do not repair
the deployment checkout by editing it in place.

The `origin` remote in an installed checkout points to SmartDock. The
`upstream` remote is relevant only in development clones, where upstream
changes are imported deliberately on a reviewed branch.
