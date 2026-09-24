from pathlib import Path
import re

p=Path('tests/test_sidebar_widgets.mjs');s=p.read_text()
s=s.replace('// Shared-scroll structure: hierarchy ListView remains the only normal scroll owner.', '// FDM-999: independent sibling scroll ownership, with one host-owned lifecycle.')
a=s.index('assert.match(viewportSource, /property Component contentTail/);')
b=s.index('assert.match(sidebarSource, /DockSidebarWidgetManager',a)
s=s[:a]+r'''assert.doesNotMatch(viewportSource, /\bcontentTail\w*\b|ContentTailDrag|footer:\s*Item/,
  'retired Widget-tail APIs must be removed, not left as unused hooks');
assert.match(viewportSource, /readonly property real naturalContentHeight:/);
assert.match(sidebarSource, /id:\s*middleRegion/);
assert.match(sidebarSource, /hierarchyContentHeight:\s*sidebarViewport\.naturalContentHeight/);
assert.match(sidebarSource, /readonly property var widgetArea:\s*sidebarWidgets/);
assert.match(sidebarSource, /height:\s*middleRegion\.split\.blankHeight/);
assert.match(sidebarSource, /anchors\.bottom:\s*pinnedStrip\.top/);
assert.doesNotMatch(sidebarSource, /widgetOverflowButton|id:\s*widgetOverflow/);
assert.doesNotMatch(areaSource, /footerLayout|openOverflow|overflowNeeded/);
const normalArea = areaSource.slice(0, areaSource.indexOf('  PopupWindow {'));
assert.equal((normalArea.match(/\bFlickable\s*\{/g) || []).length, 1);
assert.match(areaSource, /readonly property int presentedWidgetCount:\s*presentationWidgetIds\.length/);
assert.match(areaSource, /SidebarModel\.herdrFallbackVisible/);
assert.match(areaSource, /boundsBehavior:\s*Flickable\.StopAtBounds/);
assert.match(areaSource, /blocking:\s*false/);
assert.match(areaSource, /presentationClipItem:\s*widgetScroll/);
assert.match(areaSource, /presentationRevision:\s*root\.layoutRevision/);
assert.match(areaSource, /anchorOutsideViewport/);
''' +s[b:]
s=s.replace('the zero-height content tail','a zero-height Widget section').replace('the Widget tail existing','the Widget section existing').replace('shared-scroll Widget tail is absent','Widget section is absent')
a=s.index('  const viewport = {\n    contentTailDragPoint:');b=s.index('  const area = qmlMethods',a)
s=s[:a]+'''  const viewport = {};
  const widgetScroll = {width:280,height:200,contentItem:{},mapFromItem(_item,x,y){return {x,y}}};
''' +s[b:]
s=s.replace("    viewport,\n    presentationWidgetIds: ['fixture.one', 'fixture.two'],", "    viewport, widgetScroll, sectionVisible:true, presentedWidgetCount:2, pendingRestore:true,\n    layoutTimer:{restart(){}}, geometryTimer:{restart(){}},\n    presentationWidgetIds: ['fixture.one', 'fixture.two'],")
s=s.replace('  assert.ok(viewport.contentTailDragPoint);', "  assert.equal(area.dragTargetSlot, 2, 'target is computed in the independent Widget column');")
s=s.replace("  assert.equal(viewport.contentTailDragPoint, null, 'controller cancel clears autoscroll');\n  assert.ok(ended >= 1);", "  assert.equal(area.dragTargetSlot, -1, 'controller cancel clears Widget auto-scroll target');")
s=s.replace('  let ended = 0;\n','').replace('shared-scroll management helpers','split-scroll management helpers')
p.write_text(s)

p=Path('tests/test_sidebar_review_regressions.mjs');s=p.read_text()
s=s.replace('contentItem: { parent: null }','contentItem: { parent: null, visible:true, opacity:1 }')
s=s.replace('height:800, anchorY:0,','height:800, width:280, visible:true, opacity:1, anchorY:0,')
s=s.replace('return {y:this.anchorY}', 'return {x:0,y:this.anchorY}')
s=s.replace('visible: true, height:44, parent: viewport', 'visible: true, opacity:1, width:44, height:44, parent: viewport')
s=s.replace('      controller, panel, viewport,','      controller, panel, viewport, widgetScroll:viewport, sectionVisible:true, visible:true, opacity:1, parent:panel.contentItem,')
s=s.replace('    result.testViewport = viewport','    viewport.parent = result\n    viewport.contentItem = viewport\n    result.testViewport = viewport')
s=s.replace('scrolling the shared viewport','scrolling the Widget viewport')
p.write_text(s)

p=Path('tests/fixtures/widget_section_chrome.qml.in');s=p.read_text()
s=s.replace('Item { id: hierarchy; x: 14; width: parent.width - 28; property real workspaceCardInset: Style.space(5) }', 'Item { id: middle; x:14; width:parent.width-28\n        Item { id:hierarchy; x:0; width:parent.width; property real workspaceCardInset:Style.space(5) }\n      }')
s=s.replace('x: viewport.x; y: 44;', 'x: panel.viewport.parent.x + viewport.x; y: 44;')
s=s.replace('host.viewport.x + host.viewport.workspaceCardInset', 'host.viewport.parent.x + host.viewport.x + host.viewport.workspaceCardInset')
p.write_text(s)

# Native fixture: update old compact/overflow calls to the actual current pane.
# Execution still requires the FDM-1001 Omarchy guest; syntax is checked in CI.
p=Path('tests/runtime/sidebar.qml');s=p.read_text()
s=s.replace('  property var savedPopup: null', '  property var savedPopup: null\n  property var savedWidgetHeightBinding: null')
s=s.replace('  function windows() {', '''  function named(node, name) {
    if (node.objectName === name) return node
    for (var i = 0; node.children && i < node.children.length; ++i) {
      var found = root.named(node.children[i], name)
      if (found) return found
    }
    return null
  }
  function cardAnchor(area, index) {
    return root.named(area.cards.itemAt(index), "widget-card-header")
  }
  function windows() {''')
s=s.replace('footer.slots.count', 'footer.cards.count').replace('footer.slots.itemAt(0).modelData','footer.cards.itemAt(0).widgetId')
s=s.replace('footer.slots.itemAt(0).view.loadedItem', 'root.named(footer.cards.itemAt(0), "widget-card-view").loadedItem')
s=s.replace('require(h.sidebarPanel.widgetArea.slots.itemAt(0).view.presentation === "compact", "rail did not load compact factory")', 'require(h.sidebarPanel.widgetArea.height === 0 && h.sidebarPanel.widgetArea.naturalWidgetContentHeight > 0, "rail must hide Widgets without discarding body demand")')
s=re.sub(r'area\.slots\.itemAt\(([01])\)\.button',r'root.cardAnchor(area,\1)',s)
a=s.index('          area.availableContentHeight = 90');b=s.index('        } else if (root.step === 24)',a)
s=s[:a]+'''          // Test-only constrained allocation on the actual pane; restore the
          // production binding before finishing. Never write these pixels to settings.
          area.height = 0
        } else if (root.step === 21) {
          var area = h.sidebarPanel.widgetArea
          require(!area.sectionVisible && area.scrollView.height === 0, "zero allocation left an unusable section")
          require(h.sidebarPanel.widgetManageControl.visible, "main-header manager unreachable")
          h.sidebarPanel.openWidgetManager(h.sidebarPanel.widgetManageControl)
        } else if (root.step === 22) {
          require(h.sidebarPanel.widgetManager.managerOpen, "main-header manager missing at zero Widget space")
          h.sidebarPanel.widgetManager.close()
          root.widgetRequests = []
        } else if (root.step === 23) {
          require(h.sidebarPanel.widgetArea.height === 0, "disabled Widgets left an allocation")
          require(controller.widgetPopupId === "", "empty list kept a popup")
          require(widgetOne.releases === 1, "removed provider cleanup count")
          var area = h.sidebarPanel.widgetArea
          area.height = Qt.binding(function() { return area.parent.split.widgetHeight })
          root.widgetRequests = ["fixture.one"]
          h.saveSetting("sidebarEdge", "left")
''' +s[b:]
s=s.replace('widgetAnchorFactory.createObject(h.sidebarPanel.contentItem,\n            {x:0,y:h.sidebarPanel.height-44,width:44,height:44})', 'widgetAnchorFactory.createObject(area.cards.itemAt(0),\n            {x:0,y:0,width:44,height:34})')
s=s.replace('footer.scrollView.contentHeight-footer.height', 'footer.scrollView.contentHeight-footer.scrollView.height')
p.write_text(s)
