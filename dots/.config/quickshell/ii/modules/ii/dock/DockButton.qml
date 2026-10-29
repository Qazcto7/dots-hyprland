import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    Layout.fillHeight: true
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: implicitHeight - topInset - bottomInset
    buttonRadius: Appearance.rounding.normal

    background.implicitHeight: 50
}
