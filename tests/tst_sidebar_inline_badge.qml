import QtQuick
import QtTest
import "../components/DockSidebarInteractionModel.js" as InteractionModel

TestCase {
  id: test
  name: "SidebarInlineBadgeGeometry"
  when: windowShown
  width: 320
  height: 240

  function sp(n) { return Number(n) }

  function test_badgeColumnStaysFixedForNamedAndNumericWorkspaces() {
    var geometry = InteractionModel.sidebarInlineWorkspaceGeometry(5, test.sp)
    compare(geometry.badgeX, 9)
    compare(geometry.badgeWidth, 22)
    compare(geometry.stemX, 20)
    compare(geometry.artX, 39)
    compare(geometry.labelX, 61)
    compare(InteractionModel.compactWorkspaceBadgeLabel("Work"), "Wo")
    compare(InteractionModel.compactWorkspaceBadgeLabel("10"), "10")
  }

  function test_childGuideStartsUnderParentArtwork() {
    var geometry = InteractionModel.sidebarInlineWorkspaceGeometry(5, test.sp)
    compare(InteractionModel.sidebarTreeGuideColumnX(5, 1,
      geometry.guideOffset, geometry.stemOffset), geometry.stemX)
    compare(InteractionModel.sidebarTreeGuideColumnX(5, 2,
      geometry.guideOffset, geometry.stemOffset), geometry.artX + 9)
  }
}
