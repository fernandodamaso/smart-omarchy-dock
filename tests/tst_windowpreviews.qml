import QtQuick
import QtTest
import "../components/DockWindowPreviewModel.js" as PreviewModel
import "../components/DockBadgeModel.js" as BadgeModel

TestCase {
  name: "WindowPreviews"

  function test_keyedRefreshNeverChoosesAnotherWorkspace() {
    var a = { desktopId: "chrome", presentationId: "id:1/chrome" }
    var b = { desktopId: "chrome", presentationId: "id:2/chrome" }
    compare(PreviewModel.visiblePreviewTarget([a, b], b.presentationId, null), b)
    compare(PreviewModel.visiblePreviewTarget([a], b.presentationId, null), null)
    var first = {}
    var second = {}
    a.identityToplevel = first
    b.presentationId = a.presentationId
    b.identityToplevel = second
    compare(PreviewModel.visiblePreviewTarget([a, b], a.presentationId, second), b)
  }

  Component {
    id: ownerFixture
    Item {
      id: fixture
      property bool grouped: true
      property QtObject firstWindow: QtObject {}
      property QtObject secondWindow: QtObject {}
      property var items: [
        { desktopId: "chrome", presentationId: "id:1/chrome" },
        { desktopId: "chrome", presentationId: "other/chrome" },
        { desktopId: "code", presentationId: "global/code" }
      ]
      property alias delegates: owners
      Repeater {
        id: owners
        model: fixture.items
        Item {
          required property var modelData
          required property int index
          readonly property int rawIndex: fixture.items.indexOf(modelData)
          readonly property int renderedIndex: {
            if (!fixture.grouped) return index
            var items = fixture.items
            return items.indexOf(PreviewModel.visiblePreviewTarget(
              items, modelData.presentationId, modelData.identityToplevel || null))
          }
          readonly property bool owner: BadgeModel.isPrimaryVisibleItem(fixture.items, renderedIndex)
        }
      }
    }
  }

  function test_badgeOwnershipSurvivesRepeaterVariantConversion() {
    var fixture = createTemporaryObject(ownerFixture, this)
    verify(fixture)
    compare(fixture.delegates.count, 3)
    // Repeater crosses QVariant: the old lookup fails on the actual delegate.
    compare(fixture.delegates.itemAt(0).rawIndex, -1)
    for (var i = 0; i < 3; ++i)
      compare(fixture.delegates.itemAt(i).renderedIndex, i)
    compare(fixture.delegates.itemAt(0).owner, true)
    compare(fixture.delegates.itemAt(1).owner, false)
    compare(fixture.delegates.itemAt(2).owner, true)
  }

  function test_ungroupedOwnersFollowActiveWorkspaceAndWindowIdentity() {
    var fixture = createTemporaryObject(ownerFixture, this)
    verify(fixture)
    for (var workspace = 1; workspace <= 2; ++workspace) {
      fixture.items = [
        { desktopId: "chrome", presentationId: "id:" + workspace + "/chrome/pending", identityToplevel: fixture.firstWindow },
        { desktopId: "chrome", presentationId: "id:" + workspace + "/chrome/pending", identityToplevel: fixture.secondWindow },
        { desktopId: "code", presentationId: "global/code" },
        { desktopId: "chrome", presentationId: "other/chrome/abc", identityToplevel: fixture.firstWindow }
      ]
      compare(fixture.delegates.count, 4)
      for (var i = 0; i < 4; ++i)
        compare(fixture.delegates.itemAt(i).renderedIndex, i)
      compare(fixture.delegates.itemAt(0).owner, true)
      compare(fixture.delegates.itemAt(1).owner, false)
      compare(fixture.delegates.itemAt(2).owner, true)
      compare(fixture.delegates.itemAt(3).owner, false)
    }
    fixture.grouped = false
    fixture.items = [{ desktopId: "chrome" }, { desktopId: "chrome" }]
    compare(fixture.delegates.itemAt(0).renderedIndex, 0)
    compare(fixture.delegates.itemAt(1).renderedIndex, 1)
    compare(fixture.delegates.itemAt(0).owner, true)
    compare(fixture.delegates.itemAt(1).owner, false)
  }

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
