import QtQuick
import QtTest
import "../components/DockModel.js" as DockModel

TestCase {
  name: "PointerActions"

  function test_exposesCanonicalActionVocabulary() {
    compare(JSON.stringify(DockModel.applicationActionValues()), JSON.stringify([
      "none",
      "minimize-restore",
      "previews",
      "close",
      "focus-or-launch"
    ]))

    var options = DockModel.applicationActionOptions()
    compare(options.length, 5)
    compare(options[0].value, "none")
    compare(options[0].label, "No action")
    compare(options[4].value, "focus-or-launch")
    for (var optionIndex = 0; optionIndex < options.length; ++optionIndex) {
      verify(options[optionIndex].value !== "focus")
      verify(options[optionIndex].value !== "launch")
    }
  }

  function test_normalizesEachActionKeyWithKeySpecificFallbacks() {
    var values = DockModel.applicationActionValues()
    var keys = [
      "clickAction",
      "middleClickAction"
    ]

    for (var keyIndex = 0; keyIndex < keys.length; ++keyIndex) {
      for (var valueIndex = 0; valueIndex < values.length; ++valueIndex) {
        compare(DockModel.normalizeSetting(keys[keyIndex], values[valueIndex]),
          values[valueIndex])
      }
    }

    compare(DockModel.normalizeSetting("clickAction", "invalid"),
      "focus-or-launch")
    compare(DockModel.normalizeSetting("middleClickAction", "invalid"), "none")
    compare(DockModel.normalizeSetting("clickAction", "  focus  "),
      "focus-or-launch")
    compare(DockModel.normalizeSetting("clickAction", "launch"),
      "focus-or-launch")
  }

  function test_migratesLegacyConfigurationsWithoutChangingLeftClickBehavior() {
    var legacy = DockModel.normalizeApplicationActionConfig({
      clickAction: "focus-or-launch"
    })

    compare(legacy.clickAction, "focus-or-launch")
    compare(legacy.middleClickAction, "none")

    var empty = DockModel.normalizeApplicationActionConfig({})
    compare(empty.clickAction, "focus-or-launch")
    compare(empty.middleClickAction, "none")
  }

  function test_resolvesPointerInputWithExactModifierPrecedence() {
    var config = {
      clickAction: "focus-or-launch",
      middleClickAction: "focus-or-launch"
    }

    compare(DockModel.resolveApplicationPointerAction(config, "right", {}),
      "context-menu")
    compare(DockModel.resolveApplicationPointerAction(config, "right", {
      shift: true, control: true, alt: true, meta: true
    }), "context-menu")

    compare(DockModel.resolveApplicationPointerAction(config, "left", {}),
      "focus-or-launch")
    compare(DockModel.resolveApplicationPointerAction(config, "left", {
      shift: true
    }), "none")
    compare(DockModel.resolveApplicationPointerAction(config, "middle", {}),
      "focus-or-launch")
    compare(DockModel.resolveApplicationPointerAction(config, "middle", {
      shift: true
    }), "none")

    compare(DockModel.resolveApplicationPointerAction(config, "left", {
      control: true
    }), "none")
    compare(DockModel.resolveApplicationPointerAction(config, "left", {
      alt: true
    }), "none")
    compare(DockModel.resolveApplicationPointerAction(config, "middle", {
      meta: true
    }), "none")
    compare(DockModel.resolveApplicationPointerAction(config, "left", {
      shift: true, control: true
    }), "none")

    compare(DockModel.resolveApplicationPointerAction(config, "unknown", {}), "none")
  }

  function test_rejectsClosedApplicationActionsExceptLaunchCompatibleActions() {
    verify(!DockModel.applicationActionCanRun("none", 0))
    verify(!DockModel.applicationActionCanRun("minimize-restore", 0))
    verify(!DockModel.applicationActionCanRun("previews", 0))
    verify(!DockModel.applicationActionCanRun("close", 0))
    verify(DockModel.applicationActionCanRun("focus-or-launch", 0))
    verify(DockModel.applicationActionCanRun("focus-or-launch", 1))
    verify(!DockModel.applicationActionCanRun("focus", 1))
    verify(!DockModel.applicationActionCanRun("launch", 1))
  }

  function test_choosesGroupedMinimizeRestoreModeAllOrNothing() {
    compare(DockModel.minimizeRestoreMode([]), "none")
    compare(DockModel.minimizeRestoreMode([
      { minimized: false }
    ]), "minimize")
    compare(DockModel.minimizeRestoreMode([
      { minimized: false },
      { minimized: true }
    ]), "minimize")
    compare(DockModel.minimizeRestoreMode([
      { minimized: true },
      { minimized: true }
    ]), "restore")
  }

  function test_resetAndMergePreserveTheTwoActionSchema() {
    var reset = DockModel.resetSettingsPatch()
    compare(reset.clickAction, "focus-or-launch")
    compare(reset.middleClickAction, "none")

    var original = {
      pinned: ["browser"],
      hiddenApplications: ["hidden.app"],
      clickAction: "focus-or-launch",
      futureOption: "keep-me"
    }
    var merged = DockModel.mergeSettings(original, {
      middleClickAction: "close"
    })

    compare(merged.clickAction, "focus-or-launch")
    compare(merged.middleClickAction, "close")
    compare(JSON.stringify(merged.pinned), JSON.stringify(["browser"]))
    compare(JSON.stringify(merged.hiddenApplications),
      JSON.stringify(["hidden.app"]))
    compare(merged.futureOption, "keep-me")
  }
}
