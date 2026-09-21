import QtQuick
import QtTest
import "../components"

TestCase {
  id: testCase
  name: "DemoWidgets"
  when: windowShown
  visible: true
  width: 480
  height: 900

  DockDemoWidgetRegistry { id: registry }

  function test_registry_exposes_four_source_owned_demo_descriptors() {
    var ids = Object.keys(registry.descriptors).sort()
    compare(ids.length, 4)
    compare(ids.join(","), [
      "demo.actions-states", "demo.display", "demo.inputs", "demo.lists"
    ].join(","))
    for (var i = 0; i < ids.length; ++i) {
      var descriptor = registry.descriptors[ids[i]]
      compare(descriptor.id, ids[i])
      verify(descriptor.available)
      verify(descriptor.expandedView !== null)
      verify(typeof descriptor.acquire === "function")
    }
  }

  function test_each_demo_lease_publishes_ready_synthetic_snapshot() {
    var ids = Object.keys(registry.descriptors)
    for (var i = 0; i < ids.length; ++i) {
      var descriptor = registry.descriptors[ids[i]]
      var lease = descriptor.acquire(testCase)
      verify(lease !== null)
      var snapshot = null
      lease.setActive(true, function(value) { snapshot = value })
      verify(snapshot !== null)
      compare(snapshot.status, "ready")
      compare(snapshot.revision, 1)
      verify(snapshot.data !== null)
      lease.setActive(false, null)
      lease.release()
    }
  }

  function test_demo_views_load_at_sidebar_width() {
    var ids = Object.keys(registry.descriptors)
    for (var i = 0; i < ids.length; ++i) {
      var descriptor = registry.descriptors[ids[i]]
      var item = createTemporaryObject(descriptor.expandedView, testCase, {width: 280})
      verify(item !== null, ids[i] + " should create")
      item.widgetContext = {data: registry.snapshotData(ids[i])}
      wait(0)
      verify(isFinite(item.implicitHeight))
      verify(item.implicitHeight > 0)
    }
  }
}
