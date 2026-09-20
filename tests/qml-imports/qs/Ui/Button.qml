import QtQuick
import QtQuick.Controls as Controls

Controls.Button {
  property string iconText: ""
  property string tooltipText: ""
  property bool focusable: true
  activeFocusOnTab: focusable
}
