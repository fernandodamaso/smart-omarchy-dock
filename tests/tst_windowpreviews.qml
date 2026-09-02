import QtQuick
import QtTest
import "../components/DockWindowPreviewModel.js" as PreviewModel

TestCase {
  name: "WindowPreviewModel"

  function test_groupedPreviewMembersRequiresTwoLiveMembers() {
    var a = ({ id: "a" })
    var b = ({ id: "b" })
    var stale = ({ id: "stale" })

    compare(PreviewModel.groupedPreviewMembers([a], [a]).length, 0)
    compare(PreviewModel.groupedPreviewMembers([a, stale], [a]).length, 0)

    var members = PreviewModel.groupedPreviewMembers([a, stale, b], [a, b])
    compare(members.length, 2)
    compare(members[0], a)
    compare(members[1], b)
  }

  function test_previewViewportBoundsToScreen() {
    var bounded = PreviewModel.previewViewport(1920, 1080, 2800, 1600, 8)
    compare(bounded.width, 1904)
    compare(bounded.height, 1064)

    var small = PreviewModel.previewViewport(1920, 1080, 440, 220, 8)
    compare(small.width, 440)
    compare(small.height, 220)
  }

  function test_previewAnchorOffsetCoversAllDockSides() {
    var top = PreviewModel.previewAnchorOffset("top", 56, 56, 456, 220, 8)
    compare(top.x, -200)
    compare(top.y, 64)

    var bottom = PreviewModel.previewAnchorOffset("bottom", 56, 56, 456, 220, 8)
    compare(bottom.x, -200)
    compare(bottom.y, -228)

    var left = PreviewModel.previewAnchorOffset("left", 56, 56, 456, 220, 8)
    compare(left.x, 64)
    compare(left.y, -82)

    var right = PreviewModel.previewAnchorOffset("right", 56, 56, 456, 220, 8)
    compare(right.x, -464)
    compare(right.y, -82)
  }

  function test_previewLayoutUsesDockAxis() {
    verify(PreviewModel.orientationHorizontal("top"))
    verify(PreviewModel.orientationHorizontal("bottom"))
    verify(!PreviewModel.orientationHorizontal("left"))
    verify(!PreviewModel.orientationHorizontal("right"))
  }

  function test_previewStatusUsesMinimizedOrWorkspace() {
    compare(PreviewModel.previewStatus({ minimized: true, workspace: "3" }), "Minimized")
    compare(PreviewModel.previewStatus({ minimized: false, workspace: "3" }), "Workspace 3")
    compare(PreviewModel.previewStatus({ minimized: false, workspace: "name:web" }), "Workspace web")
    compare(PreviewModel.previewStatus({ minimized: false, workspace: "" }), "Workspace unknown")
  }
}
