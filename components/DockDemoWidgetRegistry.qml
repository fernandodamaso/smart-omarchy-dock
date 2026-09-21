import QtQuick
import "widgets"

Item {
  id: root

  readonly property var descriptors: ({
    "demo.display": root.makeDescriptor("demo.display", "Demo · Display", "layout-grid", displayView),
    "demo.lists": root.makeDescriptor("demo.lists", "Demo · Lists", "app-window", listsView),
    "demo.inputs": root.makeDescriptor("demo.inputs", "Demo · Inputs", "settings-2", inputsView),
    "demo.actions-states": root.makeDescriptor("demo.actions-states", "Demo · Actions & states",
      "mouse-pointer-click", actionsView)
  })

  function makeDescriptor(widgetId, label, iconName, view) {
    return {
      id: widgetId,
      label: label,
      iconName: iconName,
      available: true,
      status: "ready",
      revision: 1,
      expandedView: view,
      compactView: null,
      popupView: null,
      acquire: function(owner) { return root.acquire(widgetId) }
    }
  }

  function snapshotData(widgetId) {
    if (widgetId === "demo.display") return {
      count: 0,
      status: "Healthy",
      provider: "Synthetic",
      stats: [
        {label:"Widgets", value:"4", helper:"demo cards"},
        {label:"Coverage", value:"100%", helper:"UI kit"}
      ],
      cpu: 0.42,
      memory: 0.68,
      trend: [4, 7, 5, 9, 8, 12, 11]
    }
    if (widgetId === "demo.lists") return {
      count: 3,
      rows: [
        {title:"Shared scroll", subtitle:"Hierarchy + Widgets", trailing:"Ready", reference:"#973"},
        {title:"UI kit", subtitle:"Reusable body primitives", trailing:"Ready", reference:"#975"},
        {title:"Local qualification", subtitle:"Real Omarchy session", trailing:"Next", reference:"#974",
          attention:"urgent"}
      ],
      checklist: [
        {title:"Synthetic fixture data", detail:"No external provider", done:true},
        {title:"Theme-aware semantics", detail:"Success / warning / danger", done:true},
        {title:"Real runtime qualification", detail:"Omarchy / Hyprland / Quickshell", done:false,
          reference:"#974", attention:"overdue"}
      ],
      activity: [
        {title:"Demo provider activated", detail:"Static in-memory snapshot", semantic:"info"},
        {title:"Widget framework ready", detail:"No network requests", semantic:"success"},
        {title:"Local qualification pending", detail:"FDM-974", semantic:"warning"}
      ]
    }
    if (widgetId === "demo.inputs") return {
      count: 0,
      search:"SmartDock",
      name:"Demo widget",
      notes:"Interactive controls are local demo state only.",
      limit:5,
      refresh:["Manual","5 minutes","15 minutes"]
    }
    return {
      count: 2,
      message:"Synthetic action/state examples",
      states:["loading","empty","unavailable","error","stale"]
    }
  }

  function acquire(widgetId) {
    var lease = {
      provider: root,
      active: false,
      released: false,
      setActive: function(active, publish) {
        if (lease.released) throw new Error("released demo Widget lease reused")
        lease.active = active === true
        if (lease.active && publish)
          publish({status:"ready", revision:1, data:root.snapshotData(widgetId)})
      },
      release: function() {
        if (lease.released) return
        lease.released = true
        lease.active = false
      }
    }
    return lease
  }

  Component { id: displayView; DemoWidgetDisplayBody {} }
  Component { id: listsView; DemoWidgetListsBody {} }
  Component { id: inputsView; DemoWidgetInputsBody {} }
  Component { id: actionsView; DemoWidgetActionsStatesBody {} }
}
