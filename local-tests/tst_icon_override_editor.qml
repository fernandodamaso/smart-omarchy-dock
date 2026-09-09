import QtQuick
import QtTest
import "../components" as Components

// Local Omarchy runner (real qs.Commons/qs.Ui, existing Quickshell stubs):
//   OMARCHY_PATH=/usr/share/omarchy bash tests/run_action_dropdown_settings.sh
//
// This file intentionally remains under local-tests/. It exercises real Qt image
// decoding and must not be treated as passed until run on the Omarchy machine.

TestCase {
  id: testCase

  name: "DockIconOverrideEditor"
  when: windowShown
  width: 620
  height: 460

  readonly property url pngUrl: Qt.resolvedUrl("fixtures/icon-valid.png")
  readonly property url svgUrl: Qt.resolvedUrl("fixtures/icon-valid.svg")
  readonly property url brokenUrl: Qt.resolvedUrl("fixtures/icon-broken.png")

  property string appliedDesktopId: ""
  property string appliedSource: ""
  property string restoredDesktopId: ""

  Components.DockIconOverrideEditor {
    id: editor

    x: 20
    y: 20
    width: 560
    desktopId: "chatgpt"
    applicationName: "ChatGPT"

    onApplyRequested: function(desktopId, sourceUrl) {
      testCase.appliedDesktopId = desktopId
      testCase.appliedSource = sourceUrl
    }

    onRestoreRequested: function(desktopId) {
      testCase.restoredDesktopId = desktopId
    }
  }

  SignalSpy {
    id: chooseSpy
    target: editor
    signalName: "chooseFileRequested"
  }

  SignalSpy {
    id: applySpy
    target: editor
    signalName: "applyRequested"
  }

  SignalSpy {
    id: restoreSpy
    target: editor
    signalName: "restoreRequested"
  }

  function resetEditor() {
    editor.cancelDraft()
    editor.desktopId = "chatgpt"
    editor.applicationName = "ChatGPT"
    editor.currentSource = ""
    appliedDesktopId = ""
    appliedSource = ""
    restoredDesktopId = ""
    chooseSpy.clear()
    applySpy.clear()
    restoreSpy.clear()
    wait(0)
  }

  function namedDescendants(item, name, output) {
    output = output || []
    if (!item || item.children === undefined) return output

    for (var i = 0; i < item.children.length; ++i) {
      var child = item.children[i]
      if (!child) continue
      if (child.objectName === name) output.push(child)
      namedDescendants(child, name, output)
    }
    return output
  }

  function named(item, name) {
    var matches = namedDescendants(item, name, [])
    return matches.length > 0 ? matches[matches.length - 1] : null
  }

  function textExists(item, expected) {
    if (!item || item.children === undefined) return false
    for (var i = 0; i < item.children.length; ++i) {
      var child = item.children[i]
      if (!child) continue
      if (child.text !== undefined && child.text === expected) return true
      if (textExists(child, expected)) return true
    }
    return false
  }

  function click(name) {
    var control = named(editor, name)
    verify(control !== null, "Missing control: " + name)
    control.clicked()
    wait(0)
  }

  function waitReady() {
    tryCompare(editor, "validationState", "ready", 3000)
    verify(editor.canApply)
  }

  function init() {
    resetEditor()
  }

  function test_contractCopyAndChooseIntent() {
    verify(textExists(editor,
      "Applies to all windows of this app in SmartDock only."))
    verify(textExists(editor,
      "The selected file stays in its current location."))
    verify(textExists(editor,
      "Preview only — press Apply to save."))
    compare(named(editor, "desktopIdLabel").text, "chatgpt")

    click("chooseButton")
    compare(chooseSpy.count, 1)
    compare(editor.validationState, "idle")
  }

  function test_validPngAppliesCanonicalCapturedTargetOnce() {
    editor.desktopId = " ChatGPT.desktop "
    compare(named(editor, "desktopIdLabel").text, " ChatGPT.desktop ")
    editor.selectFile(pngUrl)
    waitReady()

    compare(editor.candidateSource, String(pngUrl))
    click("applyButton")

    compare(applySpy.count, 1)
    compare(appliedDesktopId, "chatgpt")
    compare(appliedSource, String(pngUrl))
    compare(editor.validationState, "idle")
    compare(editor.candidateSource, "")
    verify(!editor.canApply)

    click("applyButton")
    compare(applySpy.count, 1)
  }

  function test_validSvgCanApply() {
    editor.selectFile(svgUrl)
    waitReady()
    compare(editor.candidateSource, String(svgUrl))

    click("applyButton")
    compare(applySpy.count, 1)
    compare(appliedDesktopId, "chatgpt")
    compare(appliedSource, String(svgUrl))
  }

  function test_brokenImageCannotApplyOrMutateCurrentSource() {
    editor.currentSource = String(pngUrl)
    editor.selectFile(brokenUrl)

    click("applyButton")
    compare(applySpy.count, 0)
    tryCompare(editor, "validationState", "error", 3000)
    verify(!editor.canApply)
    verify(editor.validationError.length > 0)
    compare(editor.currentSource, String(pngUrl))

    click("applyButton")
    compare(applySpy.count, 0)
    compare(editor.currentSource, String(pngUrl))
  }

  function test_cancelInvalidatesReadyDraftAndPreservesPersistedChoice() {
    editor.currentSource = String(svgUrl)
    editor.selectFile(pngUrl)
    waitReady()

    editor.cancelDraft()
    compare(editor.validationState, "idle")
    compare(editor.candidateSource, "")
    compare(editor.currentSource, String(svgUrl))
    verify(!editor.canApply)

    click("applyButton")
    compare(applySpy.count, 0)
  }

  function test_cancelBeforeCompletionBlocksLateResult() {
    editor.selectFile(svgUrl)
    editor.cancelDraft()
    wait(50)

    compare(editor.validationState, "idle")
    compare(editor.candidateSource, "")
    verify(!editor.canApply)
    compare(applySpy.count, 0)
  }

  function test_samePathSelectionReplacesProbeAndReloads() {
    editor.selectFile(pngUrl)
    waitReady()

    var firstProbe = named(editor, "validationProbe")
    verify(firstProbe !== null)
    compare(firstProbe.asynchronous, true)
    compare(firstProbe.cache, false)
    compare(firstProbe.sourceSize.width, 512)
    compare(firstProbe.sourceSize.height, 512)
    compare(firstProbe.fillMode, Image.PreserveAspectFit)
    verify(firstProbe.paintedWidth > firstProbe.paintedHeight)

    editor.selectFile(pngUrl)
    wait(0)

    var secondProbe = named(editor, "validationProbe")
    verify(secondProbe !== null)
    verify(secondProbe !== firstProbe)
    compare(editor.candidateSource, String(pngUrl))
    waitReady()
  }

  function test_newSelectionWinsEvenWhenPreviousProbeCanCompleteLater() {
    editor.selectFile(svgUrl)
    editor.selectFile(pngUrl)

    compare(editor.candidateSource, String(pngUrl))
    waitReady()
    wait(50)
    compare(editor.validationState, "ready")
    compare(editor.candidateSource, String(pngUrl))

    click("applyButton")
    compare(applySpy.count, 1)
    compare(appliedSource, String(pngUrl))
  }

  function test_targetAndCurrentSourceChangesInvalidateDraft() {
    editor.selectFile(pngUrl)
    waitReady()
    editor.applicationName = "ChatGPT Desktop"
    wait(0)
    compare(editor.validationState, "ready")
    verify(editor.canApply)

    editor.desktopId = "code"
    wait(50)

    compare(editor.validationState, "idle")
    compare(editor.candidateSource, "")
    verify(!editor.canApply)
    compare(applySpy.count, 0)

    editor.selectFile(svgUrl)
    waitReady()
    editor.currentSource = String(pngUrl)
    wait(50)

    compare(editor.validationState, "idle")
    compare(editor.candidateSource, "")
    verify(!editor.canApply)
    compare(applySpy.count, 0)
  }

  function test_invalidTargetAndUnsupportedSelectionStayUncommitted() {
    editor.desktopId = ""
    editor.selectFile(pngUrl)
    compare(editor.validationState, "error")
    verify(!editor.canApply)
    click("applyButton")
    compare(applySpy.count, 0)

    editor.desktopId = "unknown-application"
    editor.selectFile(pngUrl)
    compare(editor.validationState, "error")
    verify(!editor.canApply)
    click("applyButton")
    compare(applySpy.count, 0)

    editor.desktopId = "chatgpt"
    editor.selectFile("/tmp/icon.gif")
    compare(editor.validationState, "error")
    compare(editor.candidateSource, "")
    verify(!editor.canApply)
  }

  function test_restoreIsExplicitAndRequiresExistingMapping() {
    editor.currentSource = String(svgUrl)
    click("restoreButton")

    compare(restoreSpy.count, 1)
    compare(restoredDesktopId, "chatgpt")
    compare(editor.validationState, "idle")

    editor.currentSource = ""
    click("restoreButton")
    compare(restoreSpy.count, 1)
  }
}
