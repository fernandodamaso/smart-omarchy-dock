pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "DockIconModel.js" as DockIconModel

Item {
  id: root

  property string desktopId: ""
  property string applicationName: ""
  property string currentSource: ""

  signal chooseFileRequested()
  signal applyRequested(string desktopId, string sourceUrl)
  signal restoreRequested(string desktopId)

  readonly property bool canApply: draft.validationState === "ready"
    && draft.capturedDesktopId !== ""
    && draft.capturedSource !== ""
    && draft.capturedDesktopId === DockIconModel.normalizeKey(root.desktopId)
    && draft.capturedSource === draft.candidateSource
  readonly property string candidateSource: draft.candidateSource
  readonly property string validationState: draft.validationState
  readonly property string validationError: draft.validationError

  implicitWidth: Style.space(520)
  implicitHeight: editorColumn.implicitHeight

  function selectFile(url) {
    draft.selectFile(url)
  }

  function cancelDraft() {
    draft.invalidate()
  }

  QtObject {
    id: draft

    property int generation: 0
    property string candidateSource: ""
    property string capturedDesktopId: ""
    property string capturedSource: ""
    property string validationState: "idle"
    property string validationError: ""
    property var probe: null

    function invalidate() {
      generation += 1

      var previousProbe = probe
      probe = null
      if (previousProbe) {
        previousProbe.source = ""
        previousProbe.destroy()
      }

      candidateSource = ""
      capturedDesktopId = ""
      capturedSource = ""
      validationState = "idle"
      validationError = ""
    }

    function selectFile(value) {
      invalidate()

      var key = DockIconModel.normalizeKey(root.desktopId)
      var source = DockIconModel.normalizeSource(
        value === undefined || value === null ? "" : String(value))
      candidateSource = source

      if (!key) {
        validationState = "error"
        validationError = "Select a valid application before choosing an icon."
        return
      }

      if (!source) {
        validationState = "error"
        validationError = "Select a local PNG or SVG file."
        return
      }

      capturedDesktopId = key
      capturedSource = source
      validationState = "loading"

      var token = generation
      var image = probeComponent.createObject(previewHost)
      if (!image) {
        validationState = "error"
        validationError = "The selected image could not be loaded."
        return
      }

      probe = image
      image.statusChanged.connect(function() {
        draft.observeProbe(image, token, key, source)
      })
      image.source = source
      observeProbe(image, token, key, source)
    }

    function observeProbe(image, token, key, source) {
      if (probe !== image
          || generation !== token
          || capturedDesktopId !== key
          || capturedSource !== source
          || candidateSource !== source
          || DockIconModel.normalizeKey(root.desktopId) !== key)
        return

      if (image.status === Image.Ready) {
        validationState = "ready"
        validationError = ""
      } else if (image.status === Image.Error) {
        validationState = "error"
        validationError = "The selected image could not be loaded."
      } else {
        validationState = "loading"
        validationError = ""
      }
    }

    function apply() {
      if (!root.canApply) return

      var targetId = capturedDesktopId
      var targetSource = capturedSource
      invalidate()
      root.applyRequested(targetId, targetSource)
    }

    function restore() {
      var targetId = DockIconModel.normalizeKey(root.desktopId)
      var mappedSource = DockIconModel.normalizeSource(root.currentSource)
      if (!targetId || !mappedSource) return

      invalidate()
      root.restoreRequested(targetId)
    }
  }

  Connections {
    target: root

    function onDesktopIdChanged() {
      draft.invalidate()
    }

    function onCurrentSourceChanged() {
      draft.invalidate()
    }
  }

  Component {
    id: probeComponent

    Image {
      objectName: "validationProbe"
      anchors.fill: parent
      asynchronous: true
      cache: false
      sourceSize.width: 512
      sourceSize.height: 512
      fillMode: Image.PreserveAspectFit
      smooth: true
    }
  }

  Column {
    id: editorColumn

    width: root.width
    spacing: Style.spacing.md

    Column {
      width: parent.width
      spacing: Style.spacing.xs

      Text {
        width: parent.width
        text: root.applicationName || root.desktopId || "Application"
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        objectName: "desktopIdLabel"
        width: parent.width
        text: root.desktopId
        color: Util.alpha(Color.menu.text, 0.52)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
      }
    }

    Text {
      width: parent.width
      text: "Applies to all windows of this app in SmartDock only."
      color: Util.alpha(Color.menu.text, 0.72)
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }

    Text {
      width: parent.width
      text: "The selected file stays in its current location."
      color: Util.alpha(Color.menu.text, 0.72)
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }

    Row {
      width: parent.width
      spacing: Style.spacing.md

      BorderSurface {
        width: Style.space(112)
        height: width
        radius: Style.cornerRadius
        color: Util.alpha(Color.menu.text, 0.025)
        borderSpec: Border.controlSpec("normal", Color.menu.text, Color.accent)

        Item {
          id: previewHost

          anchors.fill: parent
          anchors.margins: Style.spacing.md
        }

        Text {
          anchors.centerIn: parent
          width: parent.width - Style.spacing.lg * 2
          visible: root.candidateSource === ""
          text: "No preview"
          horizontalAlignment: Text.AlignHCenter
          color: Util.alpha(Color.menu.text, 0.45)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      Column {
        width: Math.max(0, parent.width - Style.space(112) - parent.spacing)
        spacing: Style.spacing.sm

        TextField {
          objectName: "candidateSourceField"
          width: parent.width
          text: root.candidateSource
          placeholderText: "Choose a local PNG or SVG"
          foreground: Color.menu.text
          accent: Color.accent
          readOnly: true
        }

        Text {
          width: parent.width
          text: "Preview only — press Apply to save."
          color: Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: root.validationState === "loading"
          text: "Checking image…"
          color: Util.alpha(Color.menu.text, 0.62)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          visible: root.validationError !== ""
          text: root.validationError
          color: Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }

    Flow {
      width: parent.width
      spacing: Style.spacing.sm

      Button {
        objectName: "chooseButton"
        text: "Choose file…"
        focusable: true
        bordered: true
        foreground: Color.menu.text
        background: "transparent"
        accent: Color.accent
        enabled: DockIconModel.normalizeKey(root.desktopId) !== ""
        onClicked: root.chooseFileRequested()
      }

      Button {
        objectName: "applyButton"
        text: "Apply"
        focusable: true
        bordered: true
        foreground: Color.menu.text
        background: "transparent"
        accent: Color.accent
        enabled: root.canApply
        onClicked: draft.apply()
      }

      Button {
        objectName: "cancelButton"
        text: "Cancel"
        focusable: true
        bordered: true
        foreground: Color.menu.text
        background: "transparent"
        accent: Color.accent
        enabled: root.validationState !== "idle"
          || root.candidateSource !== ""
        onClicked: root.cancelDraft()
      }

      Button {
        objectName: "restoreButton"
        text: "Restore default icon"
        focusable: true
        bordered: true
        foreground: Color.urgent
        background: "transparent"
        accent: Color.urgent
        enabled: DockIconModel.normalizeKey(root.desktopId) !== ""
          && DockIconModel.normalizeSource(root.currentSource) !== ""
        onClicked: draft.restore()
      }
    }
  }
}
