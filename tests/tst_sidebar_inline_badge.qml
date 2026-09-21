import QtQuick
import QtTest
import "../components/DockSidebarInteractionModel.js" as InteractionModel

// Real font-metric evidence for inline workspace chips.
//
// Blocker: host qmltestrunner cannot load components/DockSidebarRow.qml or
// components/DockSidebarViewport.qml (Quickshell.Widgets native plugin), so
// this fixture mirrors the production badge Text byte-for-byte and drives the
// production helpers with the measured advance. It proves the contract every
// row of a workspace consumes: one measured width per label, one shared
// geometry, and connectors that start beyond the chip instead of crossing it.
TestCase {
  id: test
  name: "SidebarInlineBadgeMetrics"
  when: windowShown
  width: 320
  height: 240

  function sp(n) { return Number(n) }

  Component {
    id: badgeProbe
    Text {
      textFormat: Text.PlainText
      font.family: "monospace" // production default Style.font.family
      font.pixelSize: 10       // production default Style.font.caption
      font.bold: true
      renderType: Text.NativeRendering
    }
  }

  function probe(label) {
    var item = createTemporaryObject(badgeProbe, test, { text: label })
    verify(item !== null, "badge probe instantiates")
    return item
  }

  function available(contentWidth) {
    return InteractionModel.sidebarInlineWorkspaceBadgeAvailableWidth(contentWidth, 5, test.sp)
  }

  function chipWidth(textWidth, budget) {
    return InteractionModel.sidebarInlineWorkspaceBadgeLayoutWidth(textWidth, budget, test.sp)
  }

  function test_chipTracksRealFontAdvance() {
    var one = probe("1")
    var work = probe("Work")
    verify(one.implicitWidth > 0, "Qt reports a real advance for the badge font")
    verify(work.implicitWidth > one.implicitWidth, "longer labels measure wider")
    var repeat = probe("Work")
    compare(repeat.implicitWidth, work.implicitWidth,
      "the same label and font always measure the same")
    compare(chipWidth(work.implicitWidth, available(280)),
      Math.max(24, Math.min(64, work.implicitWidth + 8)),
      "chip = measured advance + padding inside the shared bounds")
  }

  function test_everyRowOfAWorkspaceSharesOneGeometry() {
    var chip = chipWidth(probe("Work").implicitWidth, available(280))
    var leading = InteractionModel.sidebarInlineWorkspaceGeometry(5, test.sp, chip)
    var following = InteractionModel.sidebarInlineWorkspaceGeometry(5, test.sp, chip)
    compare(following.badgeX, leading.badgeX, "chips share their left edge")
    compare(following.artX, leading.artX, "artwork columns align")
    compare(following.labelX, leading.labelX, "labels align")
    compare(following.stemX, leading.stemX, "guide columns align")
    compare(leading.stemX, 13 + chip / 2, "the depth-1 stem sits on the chip center")
    compare(leading.artX, leading.badgeX + chip + 6 + 5,
      "artwork and the horizontal connector begin past the chip's right edge")
  }

  function test_longAndNarrowInputsClampTogether() {
    var long = probe("a-very-long-workspace-name")
    compare(chipWidth(long.implicitWidth, available(280)), 64, "ceiling")
    compare(chipWidth(probe("Workspace").implicitWidth, available(105)), 28,
      "narrow content clamps every row to the same available slot")
    compare(chipWidth(0, 0), 24, "floor")
    compare(chipWidth(NaN, undefined), 24, "missing measurement keeps the floor")
  }
}
