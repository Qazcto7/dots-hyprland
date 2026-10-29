import QtQuick

Item {
    id: root
    property var target
    property real radius: target?.radius ?? 0
    property real blur: 0
    property real spread: 0
    property var offset: Qt.vector2d(0, 0)
    property color color: "transparent"
    property bool cached: false
    visible: false
}
