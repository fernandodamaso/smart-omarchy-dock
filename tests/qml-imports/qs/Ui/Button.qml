import QtQuick
import QtQuick.Controls as Controls

Controls.Button {
  id: root
  property string iconText: ""
  property string tooltipText: ""
  property bool focusable: false
  activeFocusOnTab: focusable
  // Omarchy Button activates these keys on press; Controls.Button only does Space.
  Keys.onReturnPressed: if (focusable) root.clicked()
  Keys.onEnterPressed: if (focusable) root.clicked()
  Keys.onSpacePressed: if (focusable) root.clicked()
}
