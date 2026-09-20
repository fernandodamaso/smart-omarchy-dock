import QtQuick
import qs.Commons

Text {
  id: root
  property string role: "body"
  property bool muted: false
  property bool allowWrap: true
  property int maxLines: 0

  textFormat: Text.PlainText
  color: root.muted ? Util.alpha(Color.foreground, 0.62) : Color.foreground
  font.family: Style.font.family
  font.pixelSize: root.role === "title" ? Style.font.body
    : root.role === "caption" ? Style.font.caption : Style.font.bodySmall
  font.bold: root.role === "title" || root.role === "label"
  wrapMode: root.allowWrap ? Text.Wrap : Text.NoWrap
  elide: root.allowWrap ? Text.ElideNone : Text.ElideRight
  maximumLineCount: root.maxLines > 0 ? root.maxLines : 1000000
  clip: true
}