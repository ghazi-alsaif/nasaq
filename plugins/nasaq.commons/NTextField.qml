import QtQuick
Rectangle {
  id: tf
  property alias text: input.text
  property string placeholder: ""
  property bool password: false
  signal accepted(string text)
  signal edited(string text)
  width: 220; height: 28; radius: 8
  color: Qt.rgba(1, 1, 1, input.activeFocus ? 0.18 : 0.12)
  border.color: input.activeFocus ? Theme.accent : "transparent"
  TextInput {
    id: input
    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
    verticalAlignment: TextInput.AlignVCenter
    color: Theme.text
    font.family: Theme.textFont; font.pixelSize: Theme.fontSize
    echoMode: tf.password ? TextInput.Password : TextInput.Normal
    clip: true
    selectByMouse: true
    onAccepted: tf.accepted(text)
    onTextEdited: tf.edited(text)
    Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; text: Tr.s(tf.placeholder); visible: !input.text && !input.activeFocus; color: Theme.faint; font: input.font }
  }
}
