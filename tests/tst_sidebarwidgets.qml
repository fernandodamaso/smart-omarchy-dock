import QtQuick
import QtTest
import "../components"
import "fixtures"

TestCase {
  id: testCase
  name: "SidebarWidgets"
  when: windowShown
  // TestCase is hidden by default; popup anchors need an actual visible parent.
  visible: true
  width: 640; height: 480
  QtObject { id: writer; function saveSetting(key,value) { return {ok:true,data:{applied:true}} } }
  Component { id: factory; DockSidebarController { host: writer } }
  Component { id: providerFactory; SidebarWidgetFixture {} }
  Component { id: invalidViewFactory; Item { implicitHeight:44 } }
  Component { id: viewFactory; DockSidebarWidgetView {} }
  Component { id: anchorFactory; Item { width:44; height:44 } }
  Component { id: windowFactory; QtObject { property string appId: "browser"; property string title: "Actual window" } }
  function build(provider) {
    var screen = {name:"DP-1",width:1920,height:1080}
    var window = createTemporaryObject(windowFactory, testCase, {title: "Window A"})
    var windowB = createTemporaryObject(windowFactory, testCase, {title: "Window B"})
    var c = createTemporaryObject(factory,testCase,{
      widgetRegistry:{"fixture.one":provider.descriptor},
      settings:{presentationMode:"sidebar",sidebarWidgets:["fixture.one"],pinned:[]},
      screens:[screen],monitors:[{id:0,name:"DP-1",activeWorkspace:{id:1}}],
      workspaces:[{id:1,monitorID:0}],toplevels:[window, windowB],
      hyprToplevels:[{wayland:window,address:"0xa",lastIpcObject:{workspace:{id:1},monitor:0}},
        {wayland:windowB,address:"0xb",lastIpcObject:{workspace:{id:1},monitor:0}}]
    })
    verify(c !== null)
    c.refresh()
    return c
  }
  function test_empty_registry_and_unknown_imports() {
    var c = createTemporaryObject(factory,testCase,{settings:{sidebarWidgets:["future.clock"]}})
    compare(c.widgetIds.length,1)
    compare(c.widgetView("future.clock").status,"unavailable")
    compare(c.widgetManager.diagnostics().counters.acquisitions,0)
    c.settings={sidebarWidgets:[]}; c.refresh()
    compare(c.widgetIds.length,0)
  }
  function test_views_do_not_own_subscriptions_and_navigation_survives_errors() {
    var p = createTemporaryObject(providerFactory,testCase)
    var c = build(p)
    compare(p.acquisitions,1); compare(p.starts,1); compare(p.subscriptions,1)
    compare(c.widgetView("fixture.one").status,"ready")
    var keys = c.projection.rows.map(function(row) { return row.key })
    for (var i=0;i<30;i++) {
      c.settings=Object.assign({},c.settings,{sidebarCollapsed:i%2===0,sidebarExpandedWidth:240+i})
      c.refresh()
    }
    compare(p.starts,1); compare(p.subscriptions,1); compare(p.releases,0)
    p.notify("event"); p.notify("event"); compare(p.notifications,1)
    p.publish("error")
    compare(c.widgetView("fixture.one").status,"error")
    compare(JSON.stringify(c.projection.rows.map(function(row) { return row.key })),JSON.stringify(keys))
    var app = c.projection.rows.filter(function(row) { return row.kind === "application" })[0]
    verify(c.toggleApplication(app.key)); c.refresh()
    verify(c.folds[app.key],"provider failure cannot disable application navigation")
    p.publish("ready")
    compare(c.widgetView("fixture.one").status,"ready")
    verify(JSON.stringify(c.widgetManager.diagnostics()).indexOf("never-log-this")<0)
    var stale=p.callbacks[0]
    c.settings=Object.assign({},c.settings,{presentationMode:"classic"}); c.refresh()
    compare(p.stops,1); compare(p.releases,0)
    stale({status:"ready",revision:9999,data:{text:"stale"}})
    c.settings=Object.assign({},c.settings,{presentationMode:"sidebar"}); c.refresh()
    compare(p.acquisitions,1); compare(p.starts,2)
    stale({status:"error",revision:99999}); compare(c.widgetView("fixture.one").status,"ready")
    c.settings=Object.assign({},c.settings,{sidebarWidgets:[]}); c.refresh()
    compare(p.releases,1); compare(p.stops,2)
    c.refresh(); compare(p.releases,1)
  }
  function test_one_popup_removal_anchor_mode_and_host_cleanup() {
    var p = createTemporaryObject(providerFactory,testCase)
    var c = build(p)
    var anchor=createTemporaryObject(anchorFactory,testCase)
    verify(anchor !== null)
    compare(anchor.visible,true,"fixture anchor must be effectively visible")
    verify(c.widgetWorkActive)
    anchor.visible=false
    verify(!c.openWidgetPopup("fixture.one",anchor),"hidden anchors fail closed")
    compare(c.widgetPopupId,"")
    anchor.visible=true
    verify(c.openWidgetPopup("fixture.one",anchor))
    compare(c.widgetPopupId,"fixture.one")
    anchor.visible=false
    compare(c.widgetPopupId,"","hiding an open popup anchor closes the session")
    anchor.visible=true
    verify(c.openWidgetPopup("fixture.one",anchor))
    verify(c.openWidgetPopup("*",anchor)); compare(c.widgetPopupId,"*")
    verify(!c.openWidgetPopup("not.enabled",anchor)); compare(c.widgetPopupId,"*")
    c.closeWidgetPopup(); compare(c.widgetPopupId,"")
    verify(c.openWidgetPopup("fixture.one",anchor))
    anchor.destroy(); wait(0); compare(c.widgetPopupId,"")
    anchor=createTemporaryObject(anchorFactory,testCase)
    verify(c.openWidgetPopup("fixture.one",anchor))
    c.settings=Object.assign({},c.settings,{sidebarCollapsed:true}); c.refresh()
    compare(c.widgetPopupId,"")
    verify(c.openWidgetPopup("fixture.one",anchor))
    c.widgetRegistry={}; c.refresh(); compare(c.widgetPopupId,"")
    compare(p.releases,1)
    c.widgetRegistry={"fixture.one":p.descriptor}; c.refresh()
    verify(c.openWidgetPopup("fixture.one",anchor))
    c.screens=[]; c.refresh(); compare(c.widgetPopupId,"")
    compare(p.releases,1,"screen changes suspend but do not release an enabled provider")
    c.destroy(); wait(0); compare(p.releases,2)
  }
  function test_production_views_load_all_factories_without_new_leases() {
    var p=createTemporaryObject(providerFactory,testCase)
    var c=build(p)
    var view=createTemporaryObject(viewFactory,testCase,{controller:c,widgetId:"fixture.one",width:200,height:150})
    verify(view !== null)
    for (var i=0;i<12;i++) {
      view.presentation=["compact","expanded","popup"][i%3]
      tryCompare(view,"hasView",true)
      compare(view.loadedItem.widgetContext.id,"fixture.one")
      compare(view.loadedItem.widgetContext.presentation,view.presentation)
      verify(view.loadedItem.widgetContext.provider === p)
    }
    compare(p.acquisitions,1); compare(p.subscriptions,1); compare(p.releases,0)
    p.publish("error"); tryCompare(view,"hasView",false)
    p.publish("ready"); tryCompare(view,"hasView",true)
    view.viewEnabled=false; tryCompare(view,"hasView",false)
    compare(p.releases,0,"destroying a view does not release the host lease")
    view.destroy(); c.destroy(); wait(0); compare(p.releases,1)
  }
  function test_bad_view_is_isolated_and_recovers_without_backend_restart() {
    var p=createTemporaryObject(providerFactory,testCase)
    var c=build(p)
    var bad=Object.assign({},p.descriptor,{expandedView:invalidViewFactory})
    c.widgetRegistry={"fixture.one":bad}
    var view=createTemporaryObject(viewFactory,testCase,{controller:c,widgetId:"fixture.one",width:200,height:150})
    verify(view !== null)
    tryVerify(function() { return c.widgetView("fixture.one").errorCode === "view-error" })
    compare(c.projection.rows.filter(function(row) { return row.kind === "window" }).length,2)
    c.widgetRegistry={"fixture.one":p.descriptor}
    p.publish("ready"); tryCompare(view,"hasView",true)
    compare(p.acquisitions,1); compare(p.subscriptions,1); compare(p.releases,0)
    view.destroy(); c.destroy(); wait(0); compare(p.releases,1)
  }
  function test_shared_owner_survives_sidebar_teardown() {
    var p=createTemporaryObject(providerFactory,testCase,{externalOwners:1})
    var c=build(p)
    c.destroy(); wait(0)
    compare(p.acquisitions,1); compare(p.releases,1)
    compare(p.starts,1); compare(p.stops,0); verify(p.backendRunning)
    p.externalOwners=0; compare(p.stops,1)
  }
}
