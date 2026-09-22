import QtQuick
import QtTest
import "../components"

// The generic single-screen owner lifecycle, exercised with fake surface
// components so the assertions cover real owner behavior rather than source
// text: teardown-first replacement, one owner per output so switching one
// screen never touches another screen's surface instance, owner injection,
// and panel passthrough. DockHost wires its real Dock/DockSidebar components
// into exactly this contract.
TestCase {
  id: testCase

  name: "ScreenOwnership"
  when: windowShown
  visible: true
  width: 320
  height: 200

  // Live fake-surface count; a destroyed owner must take its surface with it.
  property int alive: 0

  Component {
    id: ownerFactory

    DockScreenPresentation {}
  }

  Component {
    id: classicFake

    Item {
      id: fake

      property var owner: null
      readonly property var panels: []
      readonly property string kind: "classic"

      Component.onCompleted: testCase.alive++
      Component.onDestruction: testCase.alive--
    }
  }

  Component {
    id: sidebarFake

    Item {
      id: fake

      property var owner: null
      readonly property var panels: [stub]
      readonly property string kind: "sidebar"

      Item {
        id: stub
      }

      Component.onCompleted: testCase.alive++
      Component.onDestruction: testCase.alive--
    }
  }

  function makeOwner(props) {
    var owner = createTemporaryObject(ownerFactory, testCase, props)
    verify(owner !== null)
    return owner
  }

  // syncSurface defers creation through Qt.callLater; one event-loop turn is
  // enough for activation.
  function settle() {
    wait(10)
  }

  function init() {
    alive = 0
  }

  function test_owner_creates_its_surface_and_injects_itself() {
    var owner = makeOwner({ connector: "DP-1", mode: "classic",
      surfaceComponent: classicFake })
    settle()
    verify(owner.surfaceReady)
    compare(owner.surface.kind, "classic")
    compare(owner.surface.owner, owner, "the loaded surface receives its owner")
    compare(owner.panels.length, 0, "classic surfaces expose no sidebar panels")
  }

  function test_panels_come_from_the_surface() {
    var owner = makeOwner({ connector: "DP-1", mode: "sidebar",
      surfaceComponent: sidebarFake })
    settle()
    compare(owner.panels.length, 1, "sidebar surfaces expose their panel")
    compare(owner.panels[0], owner.surface.panels[0])
  }

  function test_switching_one_screen_preserves_every_other_instance() {
    var a = makeOwner({ connector: "DP-1", mode: "classic",
      surfaceComponent: classicFake })
    var b = makeOwner({ connector: "DP-2", mode: "sidebar",
      surfaceComponent: sidebarFake })
    settle()
    var aSurface = a.surface
    var bSurface = b.surface
    verify(aSurface !== null && bSurface !== null)

    // A mode change moves both the surfaceKey binding and the component.
    a.mode = "sidebar"
    a.surfaceComponent = sidebarFake
    compare(a.surface, null, "teardown is synchronous: two surfaces never coexist")
    compare(b.surface, bSurface, "the untouched output keeps its surface")
    settle()
    verify(a.surface !== null && a.surface !== aSurface, "a replacement appears")
    compare(a.surface.kind, "sidebar")
    compare(b.surface, bSurface,
      "the other output still keeps the very same instance after settlement")
  }

  function test_unmapped_output_has_no_surface_and_remaps() {
    var owner = makeOwner({ connector: "DP-1", mode: "classic",
      surfaceComponent: classicFake })
    settle()
    verify(owner.surfaceReady)

    owner.mapped = false
    compare(owner.surface, null, "unmapping drops the surface synchronously")
    compare(owner.panels.length, 0)
    settle()
    compare(owner.surface, null, "and never reactivates on its own")

    owner.mapped = true
    settle()
    verify(owner.surface !== null, "re-mapping restores the surface")
  }

  function test_surface_key_recreates_but_unrelated_changes_do_not() {
    var owner = makeOwner({ connector: "DP-1", mode: "sidebar",
      surfaceComponent: sidebarFake })
    settle()
    var first = owner.surface
    verify(first !== null)

    owner.source = "override"
    compare(owner.surface, first,
      "a presentation-source change keeps the surface instance")

    // The sidebar re-anchors when its configured edge moves.
    owner.surfaceKey = "sidebar:right"
    compare(owner.surface, null, "a forced recreate still tears down first")
    settle()
    verify(owner.surface !== null && owner.surface !== first)
  }

  function test_destroying_owner_destroys_its_surface() {
    var owner = makeOwner({ connector: "DP-2", mode: "sidebar",
      surfaceComponent: sidebarFake })
    settle()
    verify(owner.surface !== null)
    compare(alive, 1)

    owner.destroy()
    settle()
    compare(alive, 0, "a disconnected output takes its surface with it")
  }
}
