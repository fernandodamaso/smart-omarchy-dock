# Dockrail migration contract

This is the source-controlled migration matrix for FDM-1002. It distinguishes intentional SmartDock compatibility contracts from branding leftovers.

## Pinned baseline

- Source baseline: `4db288d5991dae7989add897ee5dc56c5542feb8`
- Pinned when FDM-1002 execution began on 2026-09-25.
- Repository cutover remains blocked until the native pre-cutover rehearsal.
- Omarchy/Quickshell/Hyprland native revisions are recorded by MIG-05, not guessed here.

## Identifier and ownership matrix

| Identifier/state | Policy |
| --- | --- |
| Product/display name | Rename to Dockrail in the branding slice. |
| `dockrail` CLI | Canonical command. |
| `smartdock` CLI | Retain as a thin compatibility entry point. |
| canonical Dockrail XDG roots | Activate only through the journaled MIG-02 migration. |
| legacy SmartDock XDG roots | Preserve as source/recovery state; never silently reset. |
| `DOCKRAIL_CONFIG` | Canonical explicit override. |
| `SMARTDOCK_CONFIG` | Retain; canonical non-empty override wins when both are set. |
| `smartdock` IPC target, `request`, apiVersion 1 | Retain unchanged. |
| `io.github.fernandodamaso.smartdock` | Retain plugin ID for this release. |
| `SmartDock.WidgetKit 1.0` | Retain; MIG-03 adds `Dockrail.WidgetKit 1.0` over the same maintained components. |
| `special:smartdock-minimized` | Retain unchanged. |
| terminal-agent desktop/application IDs | Retain stable IDs. |
| Herdr helper/provider executable names | Retain executable identities. |
| Wayland layer namespaces | Retain unchanged. |
| development recovery records/worktrees | Preserve; rebase only by explicit migration policy. |
| external widget/icon/source paths | Preserve verbatim. |
| `DockHost`, `DockModel`, `DockItem`, `dock.json` | Keep as dock-domain internals. |
| historical issues/releases/plans | Keep historical names. |

## Read-only resolver contract

`scripts/dockrail_paths.py` computes canonical and legacy roots without creating,
migrating, repairing, or deleting anything. Explicit config precedence is:
non-empty `DOCKRAIL_CONFIG`, then non-empty `SMARTDOCK_CONFIG`, then the canonical
XDG config path. An explicit missing/invalid path is authoritative and must not
fall through silently.

The migration journal/lock will live outside roots being moved under the XDG
state home in `dockrail/migrations/`. MIG-02 owns transaction/recovery and startup activation.

Read-only CLI calls, bare/help, discovery, `--cli-only`, and
`--agent-assets-only` must never initiate migration. Omarchy plugin update cannot
assume `install.sh` runs, so MIG-02 owns the single service-start bootstrap.

## Cutover gate

GitHub repository rename, canonical URL replacement, Linear project rename and
Dockrail 3.0.0 release remain blocked until a real legacy plugin + standalone
upgrade rehearsal passes. The old GitHub name is preserved as a redirect and is
not recreated as a second repository.
