import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: root
    required property DesktopEntry entry
    property bool current: false
    signal launched()
    signal contextRequested(real x, real y)

    implicitHeight: 52
    buttonRadius: Appearance.rounding.small
    colBackground: root.current ? Appearance.colors.colLayer1Hover : "transparent"
    colBackgroundHover: Appearance.colors.colLayer1Hover

    onClicked: {
        root.entry?.execute();
        root.launched();
    }
    altAction: event => {
        root.contextRequested(event.x, event.y);
    }

    contentItem: RowLayout {
        spacing: 12
        IconImage {
            Layout.leftMargin: 8
            implicitSize: 32
            source: Quickshell.iconPath(root.entry?.icon ?? "", "application-x-executable")
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                text: root.entry?.name ?? ""
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.entry?.genericName || root.entry?.comment || ""
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }
}
