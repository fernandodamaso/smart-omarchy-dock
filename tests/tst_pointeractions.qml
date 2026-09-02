import QtQuick
import QtTest
import "../components/DockModel.js" as DockModel

TestCase {
  name: "PointerActions"

  function test_exposesCanonicalActionVocabulary() {
    compare(JSON.stringify(DockModel.applicationActionValues()), JSON.stringify([
      "none",
      "focus",
      "cycle-windows",
      "minimize-restore",
      "launch",
      "previews",
      "close",
      "focus-or-launch"
    ]))

    var options = DockModel.applicationActionOptions()
    compare(options.length, 8)
    compare(options[0].value, "none")
    compare(options[0].label, "No action")
    compare(options[7].value, "focus-or-launch")
  }

  function test_normalizesEachActionKeyWithKeySpecificFallbacks() {
    var values = DockModel.applicationActionValues()
    var keys = [
      "clickAction",
      "middleClickAction",
      "shiftClickAction",
      "scrollAction"
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
    compare(DockModel.normalizeSetting("shiftClickAction", "invalid"), "none")
    compare(DockModel.normalizeSetting("scrollAction", "invalid"), "none")
    compare(DockModel.normalizeSetting("clickAction", "  focus  "), "focus")
  }

  function test_migratesLegacyConfigurationsWithoutChangingLeftClickBehavior() {
    var legacy = DockModel.normalizeApplicationActionConfig({
      clickAction: "focus-or-launch"
    })

    compare(legacy.clickAction, "focus-or-launch")
    compare(legacy.middleClickAction, "none")
    compare(legacy.shiftClickAction, "none")
    compare(legacy.scrollAction, "none")

    var empty = DockModel.normalizeApplicationActionConfig({})
    compare(empty.clickAction, "focus-or-launch")
    compare(empty.middleClickAction, "none")
    compare(empty.shiftClickAction, "none")
    compare(empty.scrollAction, "none")
  }

  function test_resolvesPointerInputWithExactModifierPrecedence() {
    var config = {
      clickAction: "focus",
      middleClickAction: "launch",
      shiftClickAction: "close",
      scrollAction: "minimize-restore"
    }

    compare(DockModel.resolveApplicationPointerAction(config, "right", {}),
      "context-menu")
    compare(DockModel.resolveApplicationPointerAction(config, "right", {
      shift: true, control: true, alt: true, meta: true
    }), "context-menu")

    compare(DockModel.resolveApplicationPointerAction(config, "left", {}), "focus")
    compare(DockModel.resolveApplicationPointerAction(config, "left", {
      shift: true
    }), "close")
    compare(DockModel.resolveApplicationPointerAction(config, "middle", {}), "launch")
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

    compare(DockModel.resolveApplicationPointerAction(config, "scroll", {}),
      "minimize-restore")
    compare(DockModel.resolveApplicationPointerAction(config, "scroll", {
      shift: true
    }), "none")
    compare(DockModel.resolveApplicationPointerAction(config, "unknown", {}), "none")
  }

  function test_rejectsClosedApplicationActionsExceptLaunchCompatibleActions() {
    verify(!DockModel.applicationActionCanRun("none", 0))
    verify(!DockModel.applicationActionCanRun("focus", 0))
    verify(!DockModel.applicationActionCanRun("cycle-windows", 0))
    verify(!DockModel.applicationActionCanRun("minimize-restore", 0))
    verify(!DockModel.applicationActionCanRun("previews", 0))
    verify(!DockModel.applicationActionCanRun("close", 0))
    verify(DockModel.applicationActionCanRun("launch", 0))
    verify(DockModel.applicationActionCanRun("focus-or-launch", 0))
    verify(DockModel.applicationActionCanRun("focus", 1))
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

  function test_accumulatesVerticalWheelDeltasIntoLogicalSteps() {
    var firstHalf = DockModel.accumulateWheelSteps(0, 0, 60)
    compare(firstHalf.steps, 0)
    compare(firstHalf.remainder, 60)

    var fullStep = DockModel.accumulateWheelSteps(firstHalf.remainder, 0, 60)
    compare(fullStep.steps, 1)
    compare(fullStep.remainder, 0)

    var negative = DockModel.accumulateWheelSteps(0, 0, -240)
    compare(negative.steps, -2)
    compare(negative.remainder, 0)

    var partialNegative = DockModel.accumulateWheelSteps(0, 0, -70)
    var completedNegative = DockModel.accumulateWheelSteps(
      partialNegative.remainder, 0, -50)
    compare(completedNegative.steps, -1)
    compare(completedNegative.remainder, 0)

    var horizontalOnly = DockModel.accumulateWheelSteps(30, 240, 0)
    compare(horizontalOnly.steps, 0)
    compare(horizontalOnly.remainder, 30)

    var mixed = DockModel.accumulateWheelSteps(0, 480, -120)
    compare(mixed.steps, -1)
    compare(mixed.remainder, 0)

    compare(DockModel.wheelStepDirection(2), 1)
    compare(DockModel.wheelStepDirection(-2), -1)
    compare(DockModel.wheelStepDirection(0), 0)
  }

  function test_resetAndMergePreserveTheFourActionSchema() {
    var reset = DockModel.resetSettingsPatch()
    compare(reset.clickAction, "focus-or-launch")
    compare(reset.middleClickAction, "none")
    compare(reset.shiftClickAction, "none")
    compare(reset.scrollAction, "none")

    var original = {
      pinned: ["browser"],
      hiddenApplications: ["hidden.app"],
      clickAction: "launch",
      futureOption: "keep-me"
    }
    var merged = DockModel.mergeSettings(original, {
      middleClickAction: "close",
      shiftClickAction: "focus",
      scrollAction: "minimize-restore"
    })

    compare(merged.clickAction, "launch")
    compare(merged.middleClickAction, "close")
    compare(merged.shiftClickAction, "focus")
    compare(merged.scrollAction, "minimize-restore")
    compare(JSON.stringify(merged.pinned), JSON.stringify(["browser"]))
    compare(JSON.stringify(merged.hiddenApplications),
      JSON.stringify(["hidden.app"]))
    compare(merged.futureOption, "keep-me")
  }
}
