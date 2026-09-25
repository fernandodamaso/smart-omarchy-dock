# FDM-999 — split-scroll source handoff

## Source and scope

Stacked base: FDM-998 / PR #114 at
`168f4924af61e5f6339df95d60b2a7f4993d70f8`, including FDM-997 / PR #113.
Integrated main: `3dcf8ad1049a202b0ae614c83fd3df8461007469`, containing the
merged FDM-994/995 / PR #111 source. Stable parent branches are not modified.
The Draft PR records the final exact head/tree, fresh normal Headless CI and
actual test results. A staging build is not normal PR acceptance evidence.

R1 allocator and canonical row demand; sibling hierarchy/Widget scrolling;
fixed section/PINNED/Applications; stable per-panel anchors; focused-descendant
reveal; viewport-owned reorder; geometry-based popup/presentation updates.
The full original reference directory is preserved. WidgetKit1.0, sparkline,
provider leases, settings writer, popup/controller ownership and provisional
FDM-994 header-drop policy are unchanged. FDM-1000 remains optional and unselected.

## Review findings and executable evidence

The new allocator test fails before its function exists; the split source test
fails before the sibling integration. The source stages run focused gates
before publication. The allocator suite covers 16 R1 cases and 100,000 seeded
finite/nonnegative/conservation/header/minimum cases, plus ID-anchor/focus cases.

Production-source QML tests cover real wheel events in both panes and at
bounds, nested native ScrollView containment, title-drag stealing, invisible
grip press/move/release/Escape, invalid drops with zero writes, threshold/valid
reorder, Tab/Backtab and actual text editing on oversized cards, removed focus,
mirrors, filtered Herdr, rail/zero space, width/collapse reflow, and fixed popup
anchors after hierarchy growth/shrink with unchanged Widget scroll position.
Production layout/row-metric extraction rejects QWARN/QFATAL and compares actual
row sizing for every current kind/alert/drag-footer variant. FDM-994 queued
confirmation is also tested with an overflowing independent Widget sibling.

Source review caught and fixed an obsolete `endContentTailDrag()` teardown
call instead of weakening the no-tail guard. A Node fixture's cross-context
identity was corrected inside its VM; actual QML ownership tests stayed intact.
A new QML regression proved that `mapFromItem()` alone did not react to scrolling:
a fully clipped card remained presentation-active. Reading `layoutRevision`
inside the intersection binding fixes it; the test must pass after that change.

Final review added direct key-event coverage for leaving the last hierarchy
alert stop: an old early return had bypassed the new pane handler. Removing it
and clearing the outgoing alert stop restores forward traversal; Backtab now
enters the last alert stop before the row. A targeted header-font reflow test
also reproduced a missing geometry notification while outer height/contentY
were unchanged; observing natural header demand now schedules restoration and
popup geometry. All three regressions fail before their corrections.

Review was inline; no independent reviewer/subagent is claimed. The earlier
saved binary bundle was damaged; this candidate is reconstructed from verified
parents using durable plaintext source changes, not claimed byte-identical to
the lost `742405e` candidate. Old screenshots/CI are not final-head evidence.

## Evidence boundaries and local continuation

The inherited native audit inspects Omarchy
`28ceaae70ebac3a0edcc21f2faa77a90dc6d404c`. That source is not proof that the
user's installed `4.0.3-1` package is identical. Tests use Qt 6.4.2 with narrow
Commons/Ui and compositor endpoint fixtures. The alpha fade needs a shader
backend; the software scenegraph intentionally omits it rather than painting
a fake tint. Xvfb/Mesa evidence is supplementary, not full-shell qualification.

FDM-1001 must continue this integrated branch, one writer at a time, and record
installed Omarchy/Qt/Quickshell/Hyprland versions. Still required: standalone
and full-shell plugin load, Omarchy validation/lint, both-edge KVM screenshots,
real touchpad/device grabs, nested-editor input, native focus/Tab/popups,
dark/light themes, fonts/scales, animations and live reload/teardown. Preserve
FDM-995's independent physical/full-host limitations and provisional decisions.
Fix demonstrated runtime defects on this candidate, then refresh exact-head CI
and affected native evidence. No merge/install/deployment/desktop preview is
performed by this source slice.

Remote completion means **remote-complete / local-validation-required** only
after final-head source gates pass. After parents land, rebuild/rebase and
retarget to main with fresh base/head evidence under `docs/DELIVERY.md`.
