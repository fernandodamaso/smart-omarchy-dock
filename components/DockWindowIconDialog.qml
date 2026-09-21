pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Dialogs
import Quickshell
import qs.Commons
import qs.Ui
import "DockIconModel.js" as DockIconModel

// FDM-927 narrow UI exception: this dialog edits only the explicitly captured
// live window rule. General icon/preferences editing remains CLI-first.
PopupWindow {
  id: root

  required property Item anchorItem
  required property var mutationController
  required property var targetValidator

  property var targetContext: null
  property string applicationId: ""
  property string capturedTitle: ""
  property string titlePattern: ""
  property string selectedSource: ""
  property string originalKey: ""
  property var expectedRule: null
  property string inlineError: ""
  property string seedWarning: ""

  function rawAppId(toplevel) {
    if (!toplevel) return ""
    return String(toplevel.appId || toplevel.app_id || "")
  }

  function openFor(targetContext) {
    if (!targetContext || !root.targetValidator(targetContext)) return false
    var toplevel = targetContext.toplevel
    root.targetContext = targetContext
    root.applicationId = DockIconModel.normalizeWindowAppId(root.rawAppId(toplevel))
    root.capturedTitle = String(toplevel && toplevel.title || "")
    var rules = root.mutationController && root.mutationController.settings
      ? DockIconModel.normalizeWindowRules(root.mutationController.settings.windowIconOverrides) : []
    var match = DockIconModel.matchWindowRule(rules, root.applicationId, root.capturedTitle)
    root.expectedRule = match ? {
      appId: match.appId, titlePattern: match.titlePattern, source: match.source
    } : null
    root.originalKey = match ? match.key : ""
    root.selectedSource = match ? match.source : ""
    root.titlePattern = match ? match.titlePattern : root.capturedTitle.trim()
    root.inlineError = ""
    root.seedWarning = ""
    if (!match && root.capturedTitle !== root.titlePattern)
      root.seedWarning = "Surrounding whitespace is removed from the saved title pattern."
    if (root.titlePattern.indexOf("*") >= 0)
      root.seedWarning = (root.seedWarning ? root.seedWarning + " " : "")
        + "A literal * is wildcard syntax and may match other window titles."
    root.visible = true
    Qt.callLater(function() { patternInput.forceActiveFocus() })
    return true
  }

  function closeDialog() {
    root.visible = false
    root.targetContext = null
    root.inlineError = ""
  }

  function validationError() {
    if (!root.targetContext || !root.targetValidator(root.targetContext))
      return "The selected window is no longer available."
    if (!root.applicationId) return "The selected window has no usable raw Wayland Application ID."
    if (!root.titlePattern.trim()) return "Title pattern cannot be empty."
    if (root.titlePattern.trim().length > 200) return "Title pattern must be at most 200 characters."
    if (/[\x00-\x1f\x7f]/.test(root.titlePattern)) return "Title pattern cannot contain control characters."
    if (!root.selectedSource) return "Choose a local PNG or SVG file."
    return ""
  }

  function mutationArguments() {
    return {
      mode: "dialog",
      originalKey: root.originalKey,
      expected: root.expectedRule,
      appId: root.applicationId,
      titlePattern: root.titlePattern,
      source: root.selectedSource
    }
  }

  function applyChange() {
    var error = root.validationError()
    if (error) { root.inlineError = error; return false }
    var reply = root.mutationController.saveWindowIconOverride("set", root.mutationArguments())
    if (reply && (reply.ok === true || (reply.data && reply.data.applied === true))) {
      root.closeDialog()
      return true
    }
    root.inlineError = reply && reply.error ? String(reply.error.message || "Icon change was not applied.")
      : "Icon change was not applied."
    return false
  }

  function resetRule() {
    if (!root.expectedRule || !root.originalKey) return false
    if (!root.targetContext || !root.targetValidator(root.targetContext)) {
      root.inlineError = "The selected window is no longer available."
      return false
    }
    var args = root.mutationArguments()
    var reply = root.mutationController.saveWindowIconOverride("reset", args)
    if (reply && (reply.ok === true || (reply.data && reply.data.applied === true))) {
      root.closeDialog()
      return true
    }
    root.inlineError = reply && reply.error ? String(reply.error.message || "Reset was not applied.")
      : "Reset was not applied."
    return false
  }

  implicitWidth: Math.min(Style.space(420), anchor.window ? anchor.window.width - Style.space(24) : Style.space(420))
  implicitHeight: Math.min(Style.space(470), anchor.window ? anchor.window.height - Style.space(24) : Style.space(470))
  color: "transparent"
  grabFocus: true

  anchor {
    window: root.anchorItem ? root.anchorItem.QsWindow.window : null
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.x: root.anchorItem ? Math.round(root.anchorItem.width / 2) : 0
    rect.y: root.anchorItem ? Math.round(root.anchorItem.height / 2) : 0
    rect.width: 1
    rect.height: 1
  }

  BorderSurface {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(1)))

    Keys.onEscapePressed: root.closeDialog()

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(18)
      spacing: Style.space(10)

      Text {
        width: parent.width
        text: "Change Window Icon"
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "This rule affects all matching current and future windows, not only this selected window."
        color: Util.alpha(Color.menu.text, 0.72)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Row {
        spacing: Style.space(12)
        Image {
          width: 76
          height: 76
          fillMode: Image.PreserveAspectFit
          source: root.selectedSource
          visible: status === Image.Ready
        }
        Rectangle {
          width: 76
          height: 76
          radius: Style.cornerRadius
          color: Util.alpha(Color.menu.text, 0.08)
          visible: root.selectedSource === ""
          Text { anchors.centerIn: parent; text: "Icon"; color: Color.menu.text }
        }
        Column {
          width: parent.parent.width - 88
          spacing: Style.space(6)
          Text {
            width: parent.width
            elide: Text.ElideMiddle
            text: root.selectedSource || "No file selected"
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Button {
            text: "Browse"
            onClicked: fileDialog.open()
          }
        }
      }

      Text { text: "Title pattern"; color: Color.menu.text; font.pixelSize: Style.font.caption }
      TextField {
        id: patternInput
        width: parent.width
        text: root.titlePattern
        onTextChanged: root.titlePattern = text
      }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "Only * is special. Matching is case-insensitive across the full title."
        color: Util.alpha(Color.menu.text, 0.68)
        font.pixelSize: Style.font.caption
      }
      Text {
        visible: root.seedWarning !== ""
        width: parent.width
        wrapMode: Text.Wrap
        text: root.seedWarning
        color: Color.menu.text
        font.pixelSize: Style.font.caption
      }

      Text { text: "Application ID"; color: Color.menu.text; font.pixelSize: Style.font.caption }
      TextField {
        width: parent.width
        text: root.applicationId
        readOnly: true
        enabled: false
      }

      Text {
        visible: root.inlineError !== ""
        width: parent.width
        wrapMode: Text.Wrap
        text: root.inlineError
        color: Color.menu.text
        font.pixelSize: Style.font.caption
      }

      Row {
        spacing: Style.space(8)
        Button {
          visible: root.expectedRule !== null
          text: "Reset"
          onClicked: root.resetRule()
        }
        Item { width: Math.max(0, parent.parent.width - 260); height: 1 }
        Button { text: "Cancel"; onClicked: root.closeDialog() }
        Button { text: "Change"; onClicked: root.applyChange() }
      }
    }
  }

  FileDialog {
    id: fileDialog
    title: "Choose PNG or SVG artwork"
    nameFilters: ["Images (*.png *.svg)"]
    onAccepted: {
      root.selectedSource = String(selectedFile)
      root.inlineError = ""
    }
  }
}
