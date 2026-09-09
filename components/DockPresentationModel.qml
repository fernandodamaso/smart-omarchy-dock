pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "DockPresentationModel.js" as PresentationModel

Item {
  id: root

  visible: false
  width: 0
  height: 0

  property var sourceItems: []
  property string keyProperty: "identity"
  property bool animationsEnabled: true
  property var presentationState: ({ entries: [], nextToken: 1, initialized: false })
  readonly property var entries: presentationState.entries
  property alias model: scriptModel

  function reconcileNow(animate) {
    presentationState = PresentationModel.reconcile(
      presentationState, sourceItems, keyProperty,
      animate === undefined ? animationsEnabled : animate)
  }

  function completeRemoval(token, exitRevision) {
    presentationState = PresentationModel.completeRemoval(
      presentationState, token, exitRevision)
  }

  function settle() {
    presentationState = PresentationModel.reconcile(
      presentationState, sourceItems, keyProperty, false)
  }

  onSourceItemsChanged: reconcileNow()
  onKeyPropertyChanged: {
    presentationState = ({ entries: [], nextToken: 1, initialized: false })
    reconcileNow(false)
  }
  onAnimationsEnabledChanged: {
    if (!animationsEnabled) settle()
  }

  Component.onCompleted: reconcileNow(false)

  ScriptModel {
    id: scriptModel
    objectProp: "token"
    values: root.entries
  }
}
