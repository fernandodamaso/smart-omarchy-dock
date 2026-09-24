from pathlib import Path
import os
import subprocess


def edit(path, old, new):
    p = Path(path)
    s = p.read_text()
    if old not in s:
        raise RuntimeError('Missing expected text in ' + path + ': ' + old[:90])
    p.write_text(s.replace(old, new))

# Real source regression from review: mapFromItem alone is not a QML
# dependency on contentY. Prove the old binding fails before correcting it.
p = Path('tests/tst_sidebarsplitscroll.qml')
s = p.read_text()
s = s[:s.rfind('}')] + '''
  function test_presentation_visibility_updates_after_scroll() {
    var f=build();settle(f)
    var first=f.area.cards.itemAt(0),second=f.area.cards.itemAt(1)
    verify(first.presentationVisible);verify(!second.presentationVisible)
    f.area.scrollView.contentY=second.y;settle(f)
    verify(!first.presentationVisible,"fully clipped card must suspend presentation")
    verify(second.presentationVisible,"newly visible card must resume presentation")
    compare(f.provider.acquisitions,3);compare(f.provider.releases,0)
  }
}
'''
p.write_text(s)
runner = os.environ.get('QMLTESTRUNNER', '/usr/lib/qt6/bin/qmltestrunner')
result = subprocess.run([runner, '-input', 'tests/tst_sidebarsplitscroll.qml', '-import', 'components',
                         '-import', 'tests/qml-imports',
                         'SidebarSplitScroll::test_presentation_visibility_updates_after_scroll'],
                        capture_output=True, text=True, timeout=30)
evidence = Path(os.environ.get('RUNNER_TEMP', '/tmp')) / 'evidence'
evidence.mkdir(exist_ok=True)
(evidence / 'presentation-red.log').write_text(result.stdout + result.stderr)
if result.returncode == 0 or 'fully clipped card must suspend presentation' not in result.stdout:
    raise RuntimeError('Review regression did not fail for the expected missing scroll dependency')
edit('components/DockSidebarWidgetArea.qml', '  function itemIntersectsViewport(item) {\n',
     '  function itemIntersectsViewport(item) {\n    // Coordinate mapping alone does not establish a scroll dependency.\n    var revision = root.layoutRevision\n')
# The structural check caught this obsolete teardown call after the tail API
# removal. Do not weaken the check: remove the now-invalid production call.
edit('components/DockSidebarViewport.qml', '    root.endContentTailDrag()\n', '')
# A contextified Node VM global has a different identity to its host proxy.
# Bind the fixture ancestry in its own context; real QML ownership stays intact.
edit('tests/test_sidebar_review_regressions.mjs', '    viewport.parent = result',
     '    // Keep fixture ancestry inside its contextified VM identity.\n    vm.runInContext("widgetScroll.parent = root", result)')
p = Path('tests/runtime/sidebar.qml')
p.write_text(p.read_text().replace('  property var savedWidgetHeightBinding: null\n', ''))

# Exercise FDM-994 queued confirmation after the hierarchy clip is reduced by
# overflowing Widgets. The unrelated Widget scroll remains panel-local.
p = Path('tests/tst_sidebardropfeedback.qml')
s = p.read_text().replace('import "../components/DockSidebarModel.js" as SidebarModel',
                        'import "../components/DockSidebarModel.js" as SidebarModel\nimport "../components/DockSidebarWidgetModel.js" as WidgetModel')
s = s[:s.rfind('}')] + '''
  Component { id: widgetScrollFactory; Flickable { width:200; height:100; contentHeight:1200; contentWidth:200; boundsBehavior:Flickable.StopAtBounds } }
  function test_confirmation_with_overflowing_widget_sibling_preserves_both_anchors() {
    var split=WidgetModel.sidebarSplitLayout({availableHeight:240,hierarchyContentHeight:720,
      widgetHeaderHeight:38,widgetContentHeight:1200,presentedWidgetCount:3,
      minHierarchyHeight:90,minWidgetHeight:72,requestedSplitPx:null})
    origin.height=split.hierarchyHeight
    var widgets=createTemporaryObject(widgetScrollFactory,test,{y:origin.height,height:split.widgetHeight-38})
    widgets.contentY=275
    var other=JSON.stringify(controller.readScrollState("HDMI-A-1",true))
    origin.previousHeightMap="split-resized"
    origin.requestRestore()
    controller.dropOperation=operation()
    tryCompare(origin,"dropFlashKey","destination")
    var item=origin.listView.itemAtIndex(origin.indexForKey("destination"))
    verify(item!==null)
    verify(item.y>=origin.listView.contentY && item.y+item.height<=origin.listView.contentY+origin.listView.height)
    compare(widgets.contentY,275)
    compare(mirror.listView.contentY,64)
    compare(JSON.stringify(controller.readScrollState("HDMI-A-1",true)),other)
    var position=origin.listView.contentY
    Qt.callLater(origin.restoreAnchor);wait(30)
    compare(origin.listView.contentY,position);compare(widgets.contentY,275)
  }
}
'''
p.write_text(s)

# Current contracts replace shared-scroll instructions, not provider APIs.
p = Path('docs/SIDEBAR_WIDGETS.md'); s = p.read_text()
s = s.replace('FDM-973 owns the shared-scroll Widget area and management foundation',
              'FDM-973 owns the management foundation; FDM-999 supersedes its shared-scroll placement')
s = s.replace('reserves zero footer height', 'reserves zero Widget-pane height')
a = s.index('## Shared-scroll layout, management and persistence')
b = s.index('`sidebarWidgets` remains the canonical ordered list', a)
s = s[:a] + '''## Split-scroll layout, management and persistence

FDM-999 gives the hierarchy and Widget bodies **independent sibling scroll
viewports** in the bounded middle region of `DockSidebar`. The Widget section
header is fixed above its body Flickable. PINNED and Applications remain fixed.
The old `contentTail` API/Loader is removed; Widgets are not domain hierarchy
rows and do not enter `visibleRows` or section-span keys.

`sidebarSplitLayout()` allocates logical pixels from canonical hierarchy row
metrics and the natural Widget header/card-column demands. Its automatic
hierarchy cap is 55% of the middle region; short content returns unused space
to the other pane. Allocated heights never feed back into natural demand.
The desired minimums are one monitor heading plus two rows and one Widget
header plus a collapsed card, each limited by actual content demand.

When those minimums cannot fit, reserve the whole Widget header if possible,
then the hierarchy minimum, then remaining Widget body space. Header-only is
valid. Below the complete header height, hide the section entirely and keep
Add/Manage reachable from the main SmartDock header. Rail and zero *presented*
Widget cards allocate zero Widget height. A filtered-out Herdr fallback does
not count as presented and retains its provider lease.

This is not the retired `min(240, 30%)` compact footer or an overflow sentinel.
There is no adjustable splitter/setting in this slice (FDM-1000 remains optional).
The actual residual blank area alone accepts mode-switch dragging.

Each panel retains an in-memory first-visible Widget ID, offset and old order.
Width/font/content/reorder changes restore that anchor after layout; removal
uses the next surviving old neighbor, then previous, then origin. Rail and
temporary zero space preserve the expanded anchor. Wheel/touch/reorder input
is not fought by restoration; focused-descendant reveal runs after pending
restoration. No scroll offsets are written to dock.json or shared across mirrors.

Vertical input over hierarchy changes hierarchy only; input over Widget bodies
changes Widgets only, even at bounds. Fixed headers/blank background change
neither. Native nested scrollables must contain vertical input at their bounds
and retain first refusal; ordinary content uses the outer Widget scroller.
Prefer a native `Controls.ScrollView` for a nested editor instead of a blanket
overlay handler. External packages need no new required property.

''' + s[b:]
s=s.replace("among Widget cards and uses the hierarchy viewport's edge auto-scroll.",
'''among Widget cards and uses only the Widget body viewport's edge auto-scroll.
A release over hierarchy, section header, PINNED, Applications, blank space or
outside the panel cancels with zero settings writes. Escape, removed source,
external order changes or invalidated ownership also cancel. Geometry is mapped
from the retained scene point on every tick; reflow is not an external reorder.''')
s=s.replace('shared-scroll Widget tail. It therefore remains available', 'independent Widget pane. It therefore remains available')
s=s.replace('the tail has zero height', 'the pane has zero height')
s=s.replace('## Verification and SB-06 handoff', '''## Focus, presentation and popup geometry

Tab proceeds from hierarchy navigation to section Add/Manage, card root/header,
collapse and enabled body controls, then PINNED and Applications/Trash. Backtab
reverses those boundaries. The pointer grip is not a keyboard stop. Collapsed,
disabled and zero-body-area controls are skipped, while offscreen controls can
be revealed. An oversized card reveals the actual focused descendant rather
than attempting to fit its entire body. A focused removed Widget transfers only
its owning panel's focus to next/previous surviving card, section manager or
main-header manager. Provider refresh and geometry changes never request focus.

`layoutRevision` covers pane/ancestor geometry, clipping, card position/size,
contentY, screen/edge and effective visibility. Cards use the Widget body's
clip, and fully clipped presentations stop animating without unloading their
bodies or stopping providers. The one controller-owned popup follows actual
anchor geometry, including split changes at unchanged contentY; hidden,
destroyed, removed or fully clipped anchors close it. Fixed section and main
manager anchors are independent of the hierarchy viewport.

## Verification and FDM-1001 handoff''')
s=s.replace('node tests/test_sidebar_widgets.mjs\n', 'node tests/test_sidebar_split_layout.mjs\nnode tests/test_sidebar_widgets.mjs\n')
s += '''
FDM-999 executable coverage additionally includes
`tests/tst_sidebarsplitscroll.qml`, `tests/test_sidebar_split_qml.py`, and the
queued-drop/overflow regression in `tests/tst_sidebardropfeedback.qml`.
The source harness executes production methods/bindings and actual Qt input;
its compositor popup endpoints and Commons/Ui dependencies are fixtures.
Full Omarchy/Quickshell rendering, device input, native grabs/tooltips and both
host modes remain FDM-1001, not claims made by headless tests.
See [the source handoff](FDM-999-split-scroll-handoff.md).
'''
p.write_text(s)

p=Path('README.md');s=p.read_text()
a=s.index('provider leases while FDM-973 renders Widget cards as a content tail')
b=s.index('`sidebarWidgets` stores enabled order',a)
s=s[:a]+'''provider leases while FDM-999 lays out independently scrollable hierarchy and
Widget body panes. The Widget header, PINNED and Applications remain fixed.
A content-aware 55% hierarchy cap returns unused space; constrained height
preserves the full Widget header when possible and otherwise hides the section
without removing the main-header Add/Manage entry. Hidden Herdr fallback cards
reserve no space while keeping their leases. This is not the retired compact
footer or a configurable splitter.
'''+s[b:];p.write_text(s)

p=Path('docs/SIDEBAR.md');s=p.read_text()
s=s.replace('a bounded footer with no production providers.',
'''a bounded footer with no production providers (historical SB-05 placement;
FDM-999 now uses independent, content-aware hierarchy and Widget panes).''')
s += '''
## Current Widget split layout — FDM-999

The middle region excludes fixed controls, PINNED, Applications and margins
once, in logical pixels. Canonical row metrics (including alerts, Herdr/browser
rows and drag footers) drive hierarchy demand, never ListView's virtualized
content-height estimate. A fixed Widget header and clipped body Flickable are
siblings of the hierarchy. Only residual blank space accepts mode dragging.
Rail/hidden Herdr/zero-card and constrained-header policies, stable-ID anchors,
focus and input ownership are specified in [SIDEBAR_WIDGETS.md](SIDEBAR_WIDGETS.md).
Existing FDM-994 origin-only confirmation and FDM-995 native boundaries remain.
''';p.write_text(s)

p=Path('docs/SIDEBAR_INTERACTIONS.md');s=p.read_text()
s=s.replace('Widget tail, footer extra height,', 'independent Widget pane, hierarchy drag-footer extra height,')
s += '''
## Independent Widget input boundary — FDM-999

Hierarchy wheel/row-drag auto-scroll stays in the hierarchy; Widget wheel/grip
edge-scroll stays in the Widget body clip. Fixed headers and residual blank
space do not scroll either pane. Nested native scrollables retain first refusal
and contain wheel input at their bounds. A passive bottom alpha fade paints no
new surface and handles no input. Widget title drags remain stealable for
scrolling; only the explicit grip reorders, and release outside the Widget body
cancels with zero writes. The actual blank-region gesture remains included in
mode-drag selection/cancellation/preview feedback.

Tab/Backtab cross the pane boundaries without changing hierarchy arrows,
Home/End or inline workspace/alert semantics. Reveal only the focused body
control after deferred anchor restoration. No geometry/provider update takes
focus. See SIDEBAR_WIDGETS.md for per-panel restoration and popup ownership.
''';p.write_text(s)

p=Path('docs/WIDGET_COMPONENTS.md');s=p.read_text()
s += '''
## Host scrolling and nested input — FDM-999

The host owns the independent outer Widget Flickable, fixed section header,
per-panel scroll anchor and focused-descendant reveal. Widget bodies continue
to supply finite natural implicit heights at their assigned width. Do not add
a second outer scroller or unload bodies merely because their card is clipped.
A genuinely nested editor may compose a native `Controls.ScrollView`; it must
contain vertical input at its bounds rather than chain into the outer Widget
or hierarchy panes. Keep child first refusal and deliberate wheel actions.
No new required WidgetKit/provider/package property is introduced.
''';p.write_text(s)

p=Path('AGENTS.md');s=p.read_text()
s=s.replace('scroll area, popup manager, typography system, semantic color palette, or generic',
            'scroll area, popup manager, typography system, semantic color palette, or generic')
anchor='must be justified by a contract the kit does not already cover.\n'
s=s.replace(anchor,anchor+'''
FDM-999 assigns one hierarchy scroll owner and one independent Widget body scroll
owner per panel; the section header and pinned/footer controls stay fixed.
Preserve natural-demand allocation, per-panel stable-ID anchors, nested-control
first refusal and the existing single host-owned provider/settings/popup owners.
See `docs/FDM-999-split-scroll-handoff.md` for the exact remote/native boundary.
''');p.write_text(s)

p=Path('docs/plans/2026-09-23-sidebar-widget-split-scroll.md');s=p.read_text()
s=s.replace('## FDM-999 / WIDGET-07 — independent Widget scroll (not implemented here)',
            '## FDM-999 / WIDGET-07 — independent Widget scroll (source candidate)')
s=s.replace('## FDM-999 / WIDGET-07 — independent Widget scroll (source candidate)\n',
'''## FDM-999 / WIDGET-07 — independent Widget scroll (source candidate)

Execution integrates PR #114 exact parent
`168f4924af61e5f6339df95d60b2a7f4993d70f8` with main
`3dcf8ad1049a202b0ae614c83fd3df8461007469` (merged PR #111).
The historical unmerged-#111 notes below describe the planning baseline, not
current branch status. PR #113/#114 remain untouched. Final candidate refs and
fresh CI belong in the Draft PR/Linear handoff. The allocator, independent
scroll/presentation/focus/popup source and executable tests implement R1;
FDM-1001 still owns full native acceptance. No FDM-1000 setting/UI is selected.
See `docs/FDM-999-split-scroll-handoff.md`.
''');p.write_text(s)

Path('docs/FDM-999-split-scroll-handoff.md').write_text('''# FDM-999 — split-scroll source handoff

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
''')
