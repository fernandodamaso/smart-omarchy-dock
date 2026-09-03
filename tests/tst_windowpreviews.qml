import QtQuick
import QtTest
import "../components/DockWindowPreviewModel.js" as PreviewModel

TestCase {
  name: "WindowPreviews"

  function test_onlyShowsGroupsWithAtLeastTwoLiveWindows() {
    var first = { title: "First" }
    var second = { title: "Second" }
    var stale = { title: "Stale" }

    compare(PreviewModel.groupedPreviewMembers(
      [first], [first, second]).length, 0)
    compare(PreviewModel.groupedPreviewMembers(
      [first, second, stale], [first, second]).length, 2)
    compare(PreviewModel.groupedPreviewMembers(
      [first, stale], [first]).length, 0)
  }

  function test_clampsPreviewToScreenBounds() {
    var viewport = PreviewModel.previewViewport(800, 600, 900, 500, 8)
    compare(viewport.width, 784)
    compare(viewport.height, 500)

    var tiny = PreviewModel.previewViewport(100, 80, 900, 500, 8)
    compare(tiny.width, 84)
    compare(tiny.height, 64)
  }

  function test_placesPreviewOnTheOppositeSideOfTheDock() {
    compare(JSON.stringify(PreviewModel.previewAnchorOffset(
      "bottom", 50, 50, 200, 100, 8)),
      JSON.stringify({ x: -75, y: -108 }))
    compare(JSON.stringify(PreviewModel.previewAnchorOffset(
      "right", 50, 50, 200, 100, 8)),
      JSON.stringify({ x: -208, y: -25 }))
  }

  function test_formatsWindowStatus() {
    compare(PreviewModel.previewStatus({ minimized: true }), "Minimized")
    compare(PreviewModel.previewStatus({ workspace: "name:dev" }),
      "Workspace dev")
    compare(PreviewModel.previewStatus({}), "Workspace unknown")
  }
}
