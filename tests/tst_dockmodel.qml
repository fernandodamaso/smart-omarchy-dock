import QtQuick
import QtTest
import "../components/DockModel.js" as DockModel

TestCase {
  name: "DockModel"

  function test_buildsAddressTargetedWindowManagementRequests() {
    compare(DockModel.normalizeWindowAddress("ABC123"), "0xabc123")
    compare(DockModel.normalizeWindowAddress("0xABC123"), "0xabc123")
    compare(DockModel.normalizeWindowAddress("0xabc; closewindow"), "")

    compare(
      DockModel.moveWindowRequest("0xabc123", 4, true),
      'hl.dsp.window.move({ window = "address:0xabc123", workspace = "4", follow = false })')
    compare(
      DockModel.moveWindowRequest("0xabc123", 4, false),
      "movetoworkspacesilent 4,address:0xabc123")
    compare(DockModel.moveWindowRequest("0xabc123", 0, true), "")

    compare(
      DockModel.floatWindowRequest("0xabc123", "toggle", true),
      'hl.dsp.window.float({ window = "address:0xabc123", action = "toggle" })')
    compare(
      DockModel.floatWindowRequest("0xabc123", "enable", false),
      "setfloating address:0xabc123")
    compare(
      DockModel.floatWindowRequest("0xabc123", "disable", false),
      "settiled address:0xabc123")

    compare(
      DockModel.pinWindowRequest("0xabc123", true),
      'hl.dsp.window.pin({ window = "address:0xabc123", action = "toggle" })')
    compare(
      DockModel.pinWindowRequest("0xabc123", false),
      "pin address:0xabc123")
  }

  function test_buildsHyprlandNativeMinimizeAndRestoreRequests() {
    compare(
      DockModel.minimizeWindowRequest("0xabc123", true),
      'hl.dsp.window.move({ window = "address:0xabc123", workspace = "special:smartdock-minimized", follow = false })')
    compare(
      DockModel.minimizeWindowRequest("0xabc123", false),
      "movetoworkspacesilent special:smartdock-minimized,address:0xabc123")

    compare(
      DockModel.restoreWindowRequest("0xabc123", "4", true),
      'hl.dsp.window.move({ window = "address:0xabc123", workspace = "4", follow = true })')
    compare(
      DockModel.restoreWindowRequest("0xabc123", "name:writing", false),
      "movetoworkspace name:writing,address:0xabc123")
    compare(DockModel.restoreWindowRequest("0xabc123", "4,closewindow", true), "")
  }

  function test_resolvesDockControlCommand() {
    compare(DockModel.controlCommand({}), "omarchy-menu toggle apps")
    compare(DockModel.controlCommand({ controlCommand: "  custom-launcher --open  " }),
      "custom-launcher --open")
    compare(DockModel.controlCommand({ controlCommand: "   " }), "omarchy-menu toggle apps")
    compare(DockModel.controlCommand(null), "omarchy-menu toggle apps")
  }

  function test_normalizesSettingsForTheConfigurationPanel() {
    compare(DockModel.normalizeSetting("iconSize", 10), 24)
    compare(DockModel.normalizeSetting("iconSize", 120), 96)
    compare(DockModel.normalizeSetting("iconSize", 41.6), 42)
    compare(DockModel.normalizeSetting("magnification", 1.13), 1.15)
    compare(DockModel.normalizeSetting("magnification", 3), 2)
    compare(DockModel.normalizeSetting("magnificationRadius", 97), 95)
    compare(DockModel.normalizeSetting("backgroundOpacity", 0.87), 0.85)
    compare(DockModel.normalizeSetting("hoverGlowEnabled", false), false)
    compare(DockModel.normalizeSetting("hoverGlowOpacity", 0.63), 0.65)
    compare(DockModel.normalizeSetting("hoverGlowOpacity", 2), 1)
    compare(DockModel.normalizeSetting("hoverGlowRadius", 31), 30)
    compare(DockModel.normalizeSetting("hoverGlowRadius", -1), 0)
    compare(DockModel.normalizeSetting("position", "left"), "left")
    compare(DockModel.normalizeSetting("position", "diagonal"), "bottom")
    compare(DockModel.normalizeSetting("clickAction", "launch"), "launch")
    compare(DockModel.normalizeSetting("clickAction", "invalid"), "focus-or-launch")
    compare(DockModel.normalizeSetting("fullLength", true), true)
    compare(DockModel.normalizeSetting("reserveSpace", false), false)
    compare(DockModel.normalizeSetting("autoHide", true), true)
    compare(DockModel.normalizeSetting("controlCommand", "  launcher --toggle  "),
      "launcher --toggle")
  }

  function test_normalizesHiddenApplicationIds() {
    compare(JSON.stringify(DockModel.normalizeApplicationIds()), "[]")
    compare(JSON.stringify(DockModel.normalizeApplicationIds(null)), "[]")
    compare(JSON.stringify(DockModel.normalizeApplicationIds("chrome")), "[]")
    compare(JSON.stringify(DockModel.normalizeApplicationIds({ id: "chrome" })), "[]")
    compare(JSON.stringify(DockModel.normalizeApplicationIds([
      "  Firefox  ", "", "   ", "fireFOX", " Chrome ", "chrome",
      "  org.example.Editor  "
    ])), JSON.stringify(["Firefox", "Chrome", "org.example.Editor"]))
    compare(JSON.stringify(DockModel.normalizeSetting(
      "hiddenApplications", ["  ChatGPT ", "chatgpt", "  "])),
      JSON.stringify(["ChatGPT"]))
  }

  function test_addsAndRemovesHiddenApplicationIdsWithoutMutatingInputs() {
    var original = ["  Firefox ", "Chrome", "firefox"]
    var added = DockModel.addHiddenApplication(original, "  CHROME  ")

    compare(JSON.stringify(original), JSON.stringify(["  Firefox ", "Chrome", "firefox"]))
    compare(JSON.stringify(added), JSON.stringify(["Firefox", "Chrome"]))

    var extended = DockModel.addHiddenApplication(added, "  org.example.Editor  ")
    compare(JSON.stringify(extended),
      JSON.stringify(["Firefox", "Chrome", "org.example.Editor"]))
    compare(JSON.stringify(added), JSON.stringify(["Firefox", "Chrome"]))

    var removed = DockModel.removeHiddenApplication(extended, " fIrEfOx ")
    compare(JSON.stringify(removed), JSON.stringify(["Chrome", "org.example.Editor"]))
    compare(JSON.stringify(extended),
      JSON.stringify(["Firefox", "Chrome", "org.example.Editor"]))
    compare(JSON.stringify(DockModel.removeHiddenApplication(
      removed, "missing")), JSON.stringify(removed))
  }

  function test_normalizesOptionalSurfaceOverrides() {
    compare(DockModel.normalizeSetting("backgroundColorEnabled", true), true)
    compare(DockModel.normalizeSetting("backgroundColorEnabled", "true"), false)
    compare(DockModel.normalizeSetting("backgroundColor", "#AABBCC"), "#aabbcc")
    compare(DockModel.normalizeSetting("borderColor", "#dd112233"), "#dd112233")
    compare(DockModel.normalizeSetting("borderColor", "#abc"), "")
    compare(DockModel.normalizeSetting("backgroundColor", "tomato"), "")
    compare(DockModel.normalizeSetting("backgroundColor", "@Accent"), "@accent")
    compare(DockModel.normalizeSetting("borderColor", " @menu.border "), "@menu.border")
    compare(DockModel.normalizeSetting("backgroundColor", "@"), "")
    compare(DockModel.normalizeSetting("borderColor", "theme.accent"), "")
    compare(DockModel.normalizeSetting("borderWidth", -2), 0)
    compare(DockModel.normalizeSetting("borderWidth", 20), 8)
    compare(DockModel.normalizeSetting("borderWidth", 3.4), 3)
  }

  function test_buildsAtomicSurfaceOverridePatches() {
    compare(DockModel.surfaceColorMode(false, "@accent"), "default")
    compare(DockModel.surfaceColorMode(true, ""), "default")
    compare(DockModel.surfaceColorMode(true, "@accent"), "token")
    compare(DockModel.surfaceColorMode(true, "#aabbcc"), "custom")

    compare(JSON.stringify(DockModel.surfaceColorPatch(
      "backgroundColorEnabled", "backgroundColor", "")),
      JSON.stringify({ backgroundColorEnabled: false }))
    compare(JSON.stringify(DockModel.surfaceColorPatch(
      "backgroundColorEnabled", "backgroundColor", "@Accent")),
      JSON.stringify({
        backgroundColorEnabled: true,
        backgroundColor: "@accent"
      }))
    compare(JSON.stringify(DockModel.surfaceColorPatch(
      "borderColorEnabled", "borderColor", "#AABBCC")),
      JSON.stringify({
        borderColorEnabled: true,
        borderColor: "#aabbcc"
      }))
    compare(JSON.stringify(DockModel.surfaceColorPatch(
      "borderColorEnabled", "borderColor", "not-a-color")), "{}")
    compare(JSON.stringify(DockModel.surfaceColorPatch(
      "autoHide", "borderColor", "@accent")), "{}")
  }

  function test_formatsColorDialogValuesForExistingHexSettings() {
    compare(DockModel.colorToHex({ r: 1, g: 0.5, b: 0, a: 1 }), "#ff8000")
    compare(DockModel.colorToHex({ r: 1, g: 0, b: 0, a: 0.5 }), "#80ff0000")
    compare(DockModel.colorToHex({ r: 0, g: 0.25, b: 1, a: 0 }), "#000040ff")
  }

  function test_usesThemeSurfaceValuesWhenOverridesAreDisabled() {
    compare(DockModel.effectiveColor(false, "#112233", "#445566"), "#445566")
    compare(DockModel.effectiveColor(true, "invalid", "#445566"), "#445566")
    compare(DockModel.effectiveColor(true, "#112233", "#445566"), "#112233")
    compare(DockModel.effectiveColor(
      true, "@accent", "#445566", { "accent": "#aabbcc" }), "#aabbcc")
    compare(DockModel.effectiveColor(
      true, "@menu.background", "#445566",
      { "menu.background": "#778899" }), "#778899")
    compare(DockModel.effectiveColor(
      false, "@accent", "#445566", { "accent": "#aabbcc" }), "#445566")
    compare(DockModel.effectiveColor(
      true, "@missing", "#445566", { "accent": "#aabbcc" }), "#445566")
    compare(DockModel.effectiveBorderWidth(false, 7, 2), 2)
    compare(DockModel.effectiveBorderWidth(true, 7, 2), 7)
    compare(DockModel.effectiveBorderWidth(true, 99, 2), 8)
  }

  function test_mapsDockControlActionsToIcons() {
    compare(DockModel.dockControlIcon("launcher", false), "rocket")
    compare(DockModel.dockControlIcon("settings", false), "settings-2")
    compare(DockModel.dockControlIcon("add", false), "plus")
    compare(DockModel.dockControlIcon("auto-hide", false), "eye-off")
    compare(DockModel.dockControlIcon("auto-hide", true), "eye")
    compare(DockModel.dockControlIcon("unknown", false), "")
  }

  function test_alignsWorkspaceGridWithDockIconCenter() {
    var bottom = DockModel.workspaceGridPosition(
      "bottom", 300, 62, 42, 64, 30)
    compare(bottom.x, 118)
    compare(bottom.y, 16)

    var top = DockModel.workspaceGridPosition(
      "top", 300, 62, 42, 64, 30)
    compare(top.x, 118)
    compare(top.y, 16)

    var left = DockModel.workspaceGridPosition(
      "left", 62, 300, 42, 30, 64)
    compare(left.x, 16)
    compare(left.y, 118)

    var right = DockModel.workspaceGridPosition(
      "right", 62, 300, 42, 30, 64)
    compare(right.x, 16)
    compare(right.y, 118)
  }

  function test_onlyReservesSpaceWhenAutoHideIsDisabled() {
    compare(DockModel.shouldReserveSpace(true, true), false)
    compare(DockModel.shouldReserveSpace(false, true), false)
    compare(DockModel.shouldReserveSpace(true, false), true)
    compare(DockModel.shouldReserveSpace(false, false), false)
  }

  function test_centersSettingsPopupInMonitorCoordinates() {
    var bottomCompact = DockModel.centeredPopupAnchor(
      "bottom", 1920, 1080, 450, 109, 460, 760, 12)
    compare(bottomCompact.x, -5)
    compare(bottomCompact.y, -811)

    var topFullLength = DockModel.centeredPopupAnchor(
      "top", 1920, 1080, 1920, 109, 460, 760, 12)
    compare(topFullLength.x, 730)
    compare(topFullLength.y, 160)

    var leftCompact = DockModel.centeredPopupAnchor(
      "left", 1920, 1080, 109, 450, 460, 760, 12)
    compare(leftCompact.x, 730)
    compare(leftCompact.y, -155)
  }

  function test_buildsResetPatchWithoutUnrelatedSettings() {
    var reset = DockModel.resetSettingsPatch()
    compare(reset.iconSize, 42)
    compare(reset.magnification, 1.2)
    compare(reset.magnificationRadius, 95)
    compare(reset.backgroundOpacity, 0.88)
    compare(reset.hoverGlowEnabled, true)
    compare(reset.hoverGlowOpacity, 0.72)
    compare(reset.hoverGlowRadius, 28)
    compare(reset.backgroundColorEnabled, false)
    compare(reset.backgroundColor, "")
    compare(reset.borderColorEnabled, false)
    compare(reset.borderColor, "")
    compare(reset.borderWidthEnabled, false)
    compare(reset.borderWidth, 2)
    compare(reset.position, "bottom")
    compare(reset.fullLength, false)
    compare(reset.reserveSpace, true)
    compare(reset.autoHide, false)
    compare(reset.clickAction, "focus-or-launch")
    compare(reset.controlCommand, "omarchy-menu toggle apps")
    verify(reset.pinned === undefined)
    verify(reset.margin === undefined)
    verify(reset.hiddenApplications === undefined)
  }

  function test_mergesSettingsWithoutDroppingPinnedOrUnknownKeys() {
    var original = {
      iconSize: 42,
      margin: 10,
      pinned: ["browser"],
      futureOption: "keep-me"
    }
    var merged = DockModel.mergeSettings(original, {
      iconSize: 58,
      autoHide: true
    })

    compare(merged.iconSize, 58)
    compare(merged.autoHide, true)
    compare(merged.margin, 10)
    compare(merged.pinned[0], "browser")
    compare(merged.futureOption, "keep-me")
    compare(original.iconSize, 42)
  }

  function test_mirrorsCompactOmarchyWorkspaceVisibility() {
    var workspaces = [
      { id: 1, toplevels: { values: [] } },
      { id: 2, toplevels: { values: [] } },
      { id: 3, toplevels: { values: [{ title: "Editor" }] } },
      { id: 4, toplevels: { values: [] } },
      { id: 7, toplevels: [{ title: "Chat" }] },
      { id: 11, toplevels: { values: [{ title: "Out of range" }] } },
      { id: -99, name: "special:minimized", toplevels: { values: [{}] } }
    ]

    compare(DockModel.visibleWorkspaceIds(workspaces, 4).join(","), "1,2,3,4,7")
    compare(DockModel.visibleWorkspaceIds([], 9).join(","), "1,2,9")
    compare(DockModel.visibleWorkspaceIds(null, -99).join(","), "1,2")
  }

  function test_countsWorkspaceWindowsFromIpcHandles() {
    var handles = [
      {
        workspace: { id: 1 },
        lastIpcObject: { workspace: { id: 2 } }
      },
      {
        workspace: { id: 1 },
        lastIpcObject: { workspace: { id: 2 } }
      },
      {
        workspace: { id: 2 },
        lastIpcObject: { workspace: { id: 1 } }
      },
      {
        lastIpcObject: { workspace: { id: 1, name: "special:smartdock-minimized" } }
      }
    ]

    compare(DockModel.workspaceWindowCount(2, handles), 2)
    compare(DockModel.workspaceWindowCount(1, handles), 1)
    compare(DockModel.workspaceWindowCount(3, handles), 0)
  }

  function test_prefersWorkspaceIpcWindowCounts() {
    var workspaces = [
      { id: 1, lastIpcObject: { windows: 1 }, toplevels: { values: [{}, {}, {}, {}] } },
      { id: 2, lastIpcObject: { windows: 2 }, toplevels: { values: [] } }
    ]

    compare(DockModel.workspaceWindowCount(1, [], workspaces), 1)
    compare(DockModel.workspaceWindowCount(2, [], workspaces), 2)
    compare(DockModel.workspaceOccupied(workspaces[0], []), true)
    compare(DockModel.workspaceOccupied(workspaces[1], []), true)
  }

  function test_prefersHyprctlWorkspaceWindowCounts() {
    var counts = DockModel.parseWorkspaceWindowCounts(
      '[{"id":1,"windows":1},{"id":2,"windows":2}]')
    compare(counts["1"], 1)
    compare(counts["2"], 2)
    compare(DockModel.workspaceWindowCount(1, [], [], counts, true), 1)
    compare(DockModel.workspaceWindowCount(2, [], [], counts, true), 2)
    compare(DockModel.workspaceWindowCount(1,
      [], [{ id: 1, lastIpcObject: { windows: 99 } }], counts, true), 1)
    compare(DockModel.workspaceWindowCount(9, [], [], counts, true), 0)
  }

  function test_refreshesWorkspaceStateForWindowEvents() {
    verify(DockModel.shouldRefreshWorkspaceState("movewindow"))
    verify(DockModel.shouldRefreshWorkspaceState("openwindow"))
    verify(DockModel.shouldRefreshWorkspaceState("focusedmon"))
    verify(!DockModel.shouldRefreshWorkspaceState("urgent"))
  }

  function test_resolvesFocusedWorkspaceFromMonitorIpc() {
    var monitors = [
      {
        focused: false,
        activeWorkspace: { id: 2 },
        lastIpcObject: {
          focused: false,
          activeWorkspace: { id: 1, name: "" }
        }
      },
      {
        focused: false,
        activeWorkspace: { id: 1 },
        lastIpcObject: {
          focused: true,
          activeWorkspace: { id: 2, name: "" }
        }
      }
    ]

    compare(DockModel.focusedWorkspaceIdFromMonitors(monitors, { id: 1 }), 2)
    compare(DockModel.focusedWorkspaceIdFromMonitors(monitors, null), 2)
  }

  function test_prefersIpcWorkspaceOccupancyForVisibility() {
    var workspaces = [
      { id: 2, lastIpcObject: { windows: 2 }, toplevels: { values: [] } },
      { id: 3, lastIpcObject: { windows: 0 }, toplevels: { values: [{ title: "Stale" }] } }
    ]
    var handles = [
      { lastIpcObject: { workspace: { id: 2 } } },
      { lastIpcObject: { workspace: { id: 2 } } }
    ]

    compare(DockModel.visibleWorkspaceIds(workspaces, 4, handles).join(","), "1,2,4")
    compare(DockModel.visibleWorkspaceIds(workspaces, 4).join(","), "1,2,4")
    compare(DockModel.visibleWorkspaceIds(
      [{ id: 3, toplevels: { values: [{ title: "Stale" }] } }], 4).join(","),
      "1,2,3,4")
  }

  function test_buildsWorkspaceFocusRequests() {
    compare(DockModel.focusWorkspaceRequest(4, true),
      'hl.dsp.focus({ workspace = "4" })')
    compare(DockModel.focusWorkspaceRequest(4, false), "workspace 4")
    compare(DockModel.focusWorkspaceRequest(0, true), "")
    compare(DockModel.focusWorkspaceRequest(11, false), "")
  }

  function test_buildsWindowFocusRequests() {
    compare(DockModel.focusWindowRequest("0xabc123", true),
      'hl.dsp.focus({ window = "address:0xabc123" })')
    compare(DockModel.focusWindowRequest("0xabc123", false),
      "focuswindow address:0xabc123")
    compare(DockModel.focusWindowRequest("invalid address", true), "")
  }

  function test_parsesTrashListings() {
    compare(DockModel.trashItemCount(""), 0)
    compare(DockModel.trashItemCount("\n\n"), 0)
    compare(DockModel.trashItemCount(
      "trash:///one\t/home/admin/one\ntrash:///two\t/home/admin/two\n"), 2)
    compare(DockModel.trashTooltip(0), "Trash — empty")
    compare(DockModel.trashTooltip(1), "Trash — 1 item")
    compare(DockModel.trashTooltip(3), "Trash — 3 items")
  }

  function test_composesThemeSurfaceOpacity() {
    compare(DockModel.surfaceOpacity(0.75), 0.75)
    compare(DockModel.surfaceOpacity(0.75, 0.5), 0.375)
    compare(DockModel.surfaceOpacity(2), 1.0)
    compare(DockModel.surfaceOpacity(-0.2), 0.0)
    compare(DockModel.surfaceOpacity(0.75, 2), 0.75)
  }

  function test_buildsFullscreenWithBarsRequests() {
    compare(
      DockModel.fakeFullscreenRequest("0xabc123", true, true),
      'hl.dsp.window.fullscreen_state({ internal = 1, client = 0, action = "set", window = "address:0xabc123" })')
    compare(
      DockModel.fakeFullscreenRequest("0xabc123", false, true),
      'hl.dsp.window.fullscreen_state({ internal = 0, client = 0, action = "set", window = "address:0xabc123" })')
    compare(DockModel.fakeFullscreenRequest("0xabc123", true, false), "")
    compare(DockModel.fakeFullscreenRequest("invalid address", true, true), "")
  }

  function test_summarizesMinimizedWindowCounts() {
    var counts = DockModel.windowStateCounts([
      { minimized: false },
      { minimized: true },
      { minimized: true }
    ])

    compare(counts.total, 3)
    compare(counts.minimized, 2)
    compare(counts.visible, 1)
  }

  function test_labelsMinimizedAndWorkspaceWindowStates() {
    compare(
      DockModel.windowStatusLabel({ minimized: true, workspace: "3" }),
      "[minimized]")
    compare(
      DockModel.windowStatusLabel({ minimized: false, workspace: "3" }),
      "[3]")
    compare(
      DockModel.windowStatusLabel({ minimized: false, workspace: "name:writing" }),
      "[writing]")
    compare(DockModel.windowStatusLabel({ minimized: false }), "")
  }

  function test_summarizesRunningWindowWorkspaces() {
    var first = { title: "First" }
    var second = { title: "Second" }
    var third = { title: "Third" }
    var fourth = { title: "Fourth" }
    var fifth = { title: "Fifth" }
    var special = { title: "Minimized" }
    var handles = [
      { wayland: first, workspace: { id: 3, name: "3" } },
      { wayland: second, workspace: { id: 1, name: "1" } },
      { wayland: third, workspace: { id: 3, name: "3" } },
      { wayland: fourth, workspace: { id: 2, name: "2" } },
      { wayland: fifth, workspace: { id: 4, name: "4" } },
      { wayland: special, workspace: { id: -99, name: "special:smartdock-minimized" } }
    ]

    compare(DockModel.workspaceBadgeText([first], handles), "3")
    compare(DockModel.workspaceBadgeText([first, third], handles), "3")
    compare(DockModel.workspaceBadgeText([first, second], handles), "1·3")
    compare(DockModel.workspaceBadgeText([first, second, third, special], handles), "1·3")
    compare(DockModel.workspaceBadgeText([first, second, fourth, fifth], handles), "1·2+")
    compare(DockModel.workspaceBadgeText([first, special], handles), "3")
    compare(DockModel.workspaceBadgeText([special], handles), "")
    compare(DockModel.workspaceBadgeText([{ title: "Unknown" }], handles), "")
  }

  function test_prefersIpcWorkspaceOverStaleObjectRelationship() {
    var window = { title: "Ghostty" }
    var staleHandles = [
      {
        wayland: window,
        workspace: { id: 1, name: "1" },
        lastIpcObject: { workspace: { id: 2, name: "2" } }
      }
    ]

    compare(DockModel.workspaceBadgeText([window], staleHandles), "2")
  }

  function test_distinguishesFakeFullscreenFromClientFullscreen() {
    compare(DockModel.isFakeFullscreen({ fullscreen: 1, fullscreenClient: 0 }), true)
    compare(DockModel.isFakeFullscreen({ fullscreen: 1, fullscreenClient: 1 }), false)
    compare(DockModel.isFakeFullscreen({ fullscreen: 0, fullscreenClient: 0 }), false)
  }

  function test_distinguishesFullscreenWithBarsFromNativeFullscreen() {
    compare(DockModel.isFullscreenWithBars({ fullscreen: 1, fullscreenClient: 0 }), true)
    compare(DockModel.isFullscreenWithBars({ fullscreen: 1, fullscreenClient: 1 }), true)
    compare(DockModel.isFullscreenWithBars({ fullscreen: 2, fullscreenClient: 2 }), false)
    compare(DockModel.isFullscreenWithBars({ fullscreen: 0, fullscreenClient: 0 }), false)
  }

  function test_findsFullscreenWithBarsOwnerOnFocusedWorkspace() {
    var first = { title: "First" }
    var second = { title: "Second" }
    var elsewhere = { title: "Elsewhere" }
    var handles = [
      {
        wayland: first,
        workspace: { id: 1 },
        lastIpcObject: { fullscreen: 0, fullscreenClient: 0 }
      },
      {
        wayland: second,
        workspace: { id: 1 },
        lastIpcObject: { fullscreen: 1, fullscreenClient: 1 }
      },
      {
        wayland: elsewhere,
        workspace: { id: 2 },
        lastIpcObject: { fullscreen: 2, fullscreenClient: 2 }
      }
    ]

    compare(DockModel.fullscreenOwner([first, second, elsewhere], handles, 1), second)
    compare(DockModel.fullscreenOwner([first, second, elsewhere], handles, 2), null)
    compare(DockModel.fullscreenOwner([first, second, elsewhere], handles, 3), null)
  }

  function test_movesFullscreenEmphasisToActiveWindow() {
    var formerOwner = { title: "Former owner" }
    var activeWindow = { title: "Active window" }
    var handles = [
      {
        wayland: formerOwner,
        workspace: { id: 1 },
        lastIpcObject: { fullscreen: 1, fullscreenClient: 0 }
      },
      {
        wayland: activeWindow,
        workspace: { id: 1 },
        lastIpcObject: { fullscreen: 0, fullscreenClient: 0 }
      }
    ]

    compare(
      DockModel.fullscreenOwner(
        [formerOwner, activeWindow], handles, 1, activeWindow),
      activeWindow)
  }

  function test_refreshesFullscreenPresentationForRelevantHyprlandEvents() {
    verify(DockModel.shouldRefreshFullscreenPresentation("activewindow"))
    verify(DockModel.shouldRefreshFullscreenPresentation("activewindowv2"))
    verify(DockModel.shouldRefreshFullscreenPresentation("fullscreen"))
    verify(DockModel.shouldRefreshFullscreenPresentation("workspacev2"))
    verify(!DockModel.shouldRefreshFullscreenPresentation("urgent"))
  }

  function test_presentsFullscreenOwnerAndFadesOtherIcons() {
    var owner = DockModel.fullscreenIconPresentation(true, true, false)
    compare(owner.scale, 1.15)
    compare(owner.opacity, 1.0)
    var hoveredOwner = DockModel.fullscreenIconPresentation(true, true, true)
    compare(hoveredOwner.scale, 1.15)
    compare(hoveredOwner.opacity, 1.0)

    var other = DockModel.fullscreenIconPresentation(true, false, false)
    compare(other.scale, 0.9)
    compare(other.opacity, 0.45)

    var hovered = DockModel.fullscreenIconPresentation(true, false, true)
    compare(hovered.scale, 1.0)
    compare(hovered.opacity, 1.0)

    var normal = DockModel.fullscreenIconPresentation(false, false, false)
    compare(normal.scale, 1.0)
    compare(normal.opacity, 1.0)
  }

  function test_cyclesThroughGroupedWindows() {
    compare(DockModel.nextToplevelIndex(-1, 2), 0)
    compare(DockModel.nextToplevelIndex(0, 2), 1)
    compare(DockModel.nextToplevelIndex(1, 2), 0)
    compare(DockModel.nextToplevelIndex(4, 2), 0)
    compare(DockModel.nextToplevelIndex(0, 0), -1)
  }

  function test_splitsUngroupedWindowsIntoSeparateDockItems() {
    var pinned = ["com.google.Chrome"]
    var entries = [
      { id: "com.google.Chrome", startupClass: "google-chrome" },
      { id: "org.wezfurlong.wezterm", startupClass: "org.wezfurlong.wezterm" }
    ]
    var chromeOne = { appId: "google-chrome", title: "Inbox" }
    var chromeTwo = { appId: "google-chrome", title: "Docs" }
    var terminal = { appId: "org.wezfurlong.wezterm", title: "Shell" }

    var items = DockModel.buildVisibleItems(
      pinned, [chromeOne, chromeTwo, terminal], entries, [], false, false)

    compare(items.length, 3)
    compare(items[0].desktopId, "com.google.Chrome")
    compare(items[0].pinned, true)
    compare(items[0].toplevels[0], chromeOne)
    compare(items[1].toplevels[0], chromeTwo)
    compare(items[2].toplevels[0], terminal)
    compare(items[1].toplevels.length, 1)
    compare(items[2].toplevels.length, 1)
  }

  function test_keepsPinnedOrderAndAppendsGroupedRunningApps() {
    var pinned = ["org.gnome.Nautilus", "com.google.Chrome"]
    var entries = [
      { id: "org.gnome.Nautilus", startupClass: "org.gnome.Nautilus" },
      { id: "com.google.Chrome", startupClass: "google-chrome" },
      { id: "org.wezfurlong.wezterm", startupClass: "org.wezfurlong.wezterm" }
    ]
    var chrome = { appId: "google-chrome", title: "Browser" }
    var terminalOne = { appId: "org.wezfurlong.wezterm", title: "Shell one" }
    var terminalTwo = { appId: "org.wezfurlong.wezterm", title: "Shell two" }

    var items = DockModel.buildVisibleItems(
      pinned, [chrome, terminalOne, terminalTwo], entries)

    compare(items.length, 3)
    compare(items[0].desktopId, "org.gnome.Nautilus")
    compare(items[1].desktopId, "com.google.Chrome")
    compare(items[1].toplevels.length, 1)
    compare(items[2].desktopId, "org.wezfurlong.wezterm")
    compare(items[2].pinned, false)
    compare(items[2].toplevels.length, 2)
  }

  function test_hidesPinnedApplicationsWithoutChangingPinnedOrder() {
    var pinned = ["org.gnome.Nautilus", "com.google.Chrome", "com.mitchellh.ghostty"]
    var entries = [
      { id: "org.gnome.Nautilus", startupClass: "org.gnome.Nautilus" },
      { id: "com.google.Chrome", startupClass: "google-chrome" },
      { id: "com.mitchellh.ghostty", startupClass: "com.mitchellh.ghostty" }
    ]
    var windows = [
      { appId: "org.gnome.Nautilus", title: "Files" },
      { appId: "google-chrome", title: "Chrome" },
      { appId: "com.mitchellh.ghostty", title: "Terminal" }
    ]

    var hidden = DockModel.addHiddenApplication([], " com.google.chrome ")
    var visible = DockModel.buildVisibleItems(pinned, windows, entries,
      [], false, hidden)

    compare(JSON.stringify(pinned), JSON.stringify([
      "org.gnome.Nautilus", "com.google.Chrome", "com.mitchellh.ghostty"
    ]))
    compare(JSON.stringify(visible.map(function(item) { return item.desktopId })),
      JSON.stringify(["org.gnome.Nautilus", "com.mitchellh.ghostty"]))

    var restored = DockModel.removeHiddenApplication(hidden, "COM.GOOGLE.CHROME")
    var restoredItems = DockModel.buildVisibleItems(pinned, windows, entries,
      [], false, restored)
    compare(JSON.stringify(restoredItems.map(function(item) {
      return item.desktopId
    })), JSON.stringify(pinned))
  }

  function test_hidesGroupedUnpinnedApplications() {
    var entries = [
      { id: "org.example.Editor", startupClass: "org.example.Editor" },
      { id: "org.example.Terminal", startupClass: "org.example.Terminal" }
    ]
    var editorOne = { appId: "org.example.Editor", title: "Editor one" }
    var editorTwo = { appId: "org.example.Editor", title: "Editor two" }
    var terminal = { appId: "org.example.Terminal", title: "Terminal" }

    var items = DockModel.buildVisibleItems([], [editorOne, editorTwo, terminal],
      entries, [], false, [" ORG.EXAMPLE.EDITOR "])

    compare(items.length, 1)
    compare(items[0].desktopId, "org.example.Terminal")
    compare(items[0].toplevels.length, 1)
  }

  function test_usesStartupClassToAssociateRunningWindowWithPinnedLauncher() {
    var pinned = ["chatgpt"]
    var entries = [
      { id: "chatgpt", startupClass: "org.omarchy.agent" }
    ]
    var codex = { appId: "org.omarchy.agent", title: "Work" }

    var items = DockModel.buildVisibleItems(pinned, [codex], entries)

    compare(items.length, 1)
    compare(items[0].desktopId, "chatgpt")
    compare(items[0].pinned, true)
    compare(items[0].toplevels.length, 1)
  }

  function test_associatesGeneratedBrowserWindowWithPinnedWebApp() {
    var pinned = ["youtube"]
    var entries = [
      {
        id: "youtube",
        startupClass: "",
        command: ["google-chrome", "--app=https://www.youtube.com/"]
      }
    ]
    var youtube = {
      appId: "chrome-wwwyoutubecom-Default",
      title: "YouTube"
    }

    var items = DockModel.buildVisibleItems(pinned, [youtube], entries)

    compare(items.length, 1)
    compare(items[0].desktopId, "youtube")
    compare(items[0].toplevels.length, 1)
  }

  function test_keepsUnmatchedRunningApplicationFocusable() {
    var window = { appId: "com.example.unknown", title: "Unknown" }

    var items = DockModel.buildVisibleItems([], [window], [])

    compare(items.length, 1)
    compare(items[0].desktopId, "com.example.unknown")
    compare(items[0].pinned, false)
    compare(items[0].toplevels[0], window)
  }

  function test_sortsOpenAppsByWorkspaceWhenSortByWorkspaceEnabled() {
    var pinned = ["org.gnome.Nautilus", "com.google.Chrome", "com.mitchellh.ghostty"]
    var entries = [
      { id: "org.gnome.Nautilus", startupClass: "org.gnome.Nautilus" },
      { id: "com.google.Chrome", startupClass: "google-chrome" },
      { id: "com.mitchellh.ghostty", startupClass: "com.mitchellh.ghostty" }
    ]
    var nautilusWindow = { appId: "org.gnome.Nautilus", title: "Files" }
    var chromeWindow = { appId: "google-chrome", title: "Chrome" }
    var ghosttyWindow = { appId: "com.mitchellh.ghostty", title: "Ghostty" }
    var firefoxWindow = { appId: "firefox", title: "Firefox" }

    var handles = [
      { wayland: nautilusWindow, lastIpcObject: { workspace: { id: 2 } } },
      { wayland: chromeWindow, lastIpcObject: { workspace: { id: 1 } } },
      { wayland: ghosttyWindow, lastIpcObject: { workspace: { id: 3 } } },
      { wayland: firefoxWindow, lastIpcObject: { workspace: { id: 2 } } }
    ]

    var items = DockModel.buildVisibleItems(
      pinned, [nautilusWindow, chromeWindow, ghosttyWindow, firefoxWindow],
      entries, handles, true)

    compare(items.length, 4)
    compare(items[0].desktopId, "com.google.Chrome")
    compare(items[1].desktopId, "org.gnome.Nautilus")
    compare(items[2].desktopId, "firefox")
    compare(items[3].desktopId, "com.mitchellh.ghostty")

    var hiddenItems = DockModel.buildVisibleItems(
      pinned, [nautilusWindow, chromeWindow, ghosttyWindow, firefoxWindow],
      entries, handles, true, [" FIREFOX "])
    compare(JSON.stringify(hiddenItems.map(function(item) {
      return item.desktopId
    })), JSON.stringify([
      "com.google.Chrome", "org.gnome.Nautilus", "com.mitchellh.ghostty"
    ]))
  }

  function test_keepsClosedPinnedAppsFirstWhenSortingByWorkspace() {
    var pinned = ["org.gnome.Nautilus", "com.google.Chrome", "com.mitchellh.ghostty"]
    var entries = [
      { id: "org.gnome.Nautilus", startupClass: "org.gnome.Nautilus" },
      { id: "com.google.Chrome", startupClass: "google-chrome" },
      { id: "com.mitchellh.ghostty", startupClass: "com.mitchellh.ghostty" }
    ]
    var chromeWindow = { appId: "google-chrome", title: "Chrome" }
    var ghosttyWindow = { appId: "com.mitchellh.ghostty", title: "Ghostty" }

    var handles = [
      { wayland: chromeWindow, lastIpcObject: { workspace: { id: 2 } } },
      { wayland: ghosttyWindow, lastIpcObject: { workspace: { id: 1 } } }
    ]

    var items = DockModel.buildVisibleItems(
      pinned, [chromeWindow, ghosttyWindow], entries, handles, true)

    compare(items.length, 3)
    compare(items[0].desktopId, "org.gnome.Nautilus")
    compare(items[1].desktopId, "com.mitchellh.ghostty")
    compare(items[2].desktopId, "com.google.Chrome")
  }
}
