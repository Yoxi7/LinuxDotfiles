pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs

// Окно Alt+Tab. Живёт постоянно и только показывается: так оно успевает получить клавиатуру
// до того, как отпустят Alt даже при быстром нажатии.
//   отпустить Alt / Enter / клик — перейти; ←→ / Tab — выбор; Q или Delete — закрыть окно; Esc — отмена
PanelWindow {
    id: win
    visible: Switcher.open
    screen: Quickshell.screens.find(s => s.name === Switcher.monitor) ?? Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "qs-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    readonly property real cardW: 248
    readonly property real thumbH: 150

    // список приложений читается в функциях — так подписи обновятся, когда DesktopEntries догрузится
    function appIcon(app) {
        void DesktopEntries.applications.values.length
        return Quickshell.iconPath(DesktopEntries.heuristicLookup(app)?.icon ?? app, "application-x-executable")
    }
    function appName(app) {
        void DesktopEntries.applications.values.length
        return DesktopEntries.heuristicLookup(app)?.name ?? app
    }

    onVisibleChanged: if (visible) keys.forceActiveFocus()

    FocusScope {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onReleased: e => {
            if (e.key === Qt.Key_Alt || e.key === Qt.Key_AltGr || e.key === Qt.Key_Meta) { Switcher.commit(); e.accepted = true }
        }
        Keys.onPressed: e => {
            const n = Switcher.items.length
            if (e.key === Qt.Key_Escape) Switcher.cancel()
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) Switcher.commit()
            else if (e.key === Qt.Key_Right || e.key === Qt.Key_Tab || e.key === Qt.Key_Down) Switcher.step(1)
            else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backtab || e.key === Qt.Key_Up) Switcher.step(-1)
            else if (e.key === Qt.Key_Q || e.key === Qt.Key_Delete) {
                const c = Switcher.items[Switcher.index]
                if (c) {
                    Quickshell.execDetached(["mmsg", "dispatch", "killclient", "client," + c.id])
                    Switcher.items = Switcher.items.filter(x => x !== c)
                    if (!Switcher.items.length) Switcher.cancel()
                    else Switcher.index = Math.min(Switcher.index, Switcher.items.length - 1)
                }
            }
            else return
            e.accepted = true
        }

        MouseArea { anchors.fill: parent; onClicked: Switcher.cancel() }

        Glass {
            id: panel
            anchors.centerIn: parent
            width: Math.min(win.width - 80, list.contentWidth + 28)
            height: win.thumbH + 124
            radius: 30
            color: Theme.glassStrong
            opacity: Switcher.shown ? 1 : 0
            scale: Switcher.shown ? 1 : 0.95
            Behavior on opacity { NumberAnimation { duration: Theme.dFast } }
            Behavior on scale { NumberAnimation { duration: Theme.dBase; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent }

            ListView {
                id: list
                anchors { fill: parent; margins: 14 }
                orientation: ListView.Horizontal
                spacing: 8
                clip: true
                model: Switcher.items
                currentIndex: Switcher.index
                highlightMoveDuration: 140
                highlightFollowsCurrentItem: true
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                boundsBehavior: Flickable.StopAtBounds
                highlight: Rectangle {
                    radius: 20
                    color: Theme.strong
                    border { width: 2; color: Theme.primary }
                }

                delegate: Item {
                    id: card
                    required property var modelData
                    required property int index
                    readonly property bool current: ListView.isCurrentItem
                    width: win.cardW
                    height: list.height

                    Column {
                        anchors { fill: parent; margins: 10 }
                        spacing: 8

                        ClippingRectangle {
                            width: parent.width
                            height: win.thumbH - 20
                            radius: 12
                            color: Qt.rgba(0, 0, 0, 0.35)

                            Image {
                                id: thumb
                                anchors.fill: parent
                                // превью из кэша (обновляется при открытии), «#…» — сбросить кэш картинки
                                source: Switcher.shown ? "file://" + Switcher.thumbDir + "/" + card.modelData.id + ".png#" + Switcher.stamp : ""
                                fillMode: Image.PreserveAspectCrop
                                cache: false
                                asynchronous: true
                                opacity: card.current ? 1 : 0.75
                                layer.enabled: Session.privacy
                                layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 48; saturation: -0.5; brightness: -0.05 }
                            }
                            Image {
                                visible: thumb.status !== Image.Ready
                                anchors.centerIn: parent
                                width: 56; height: 56
                                sourceSize { width: 112; height: 112 }
                                source: win.appIcon(card.modelData.appid)
                            }
                            // монитор и тег
                            Rectangle {
                                anchors { right: parent.right; top: parent.top; margins: 6 }
                                width: where.implicitWidth + 12
                                height: 20
                                radius: 10
                                color: Qt.rgba(0, 0, 0, 0.6)
                                Text {
                                    id: where
                                    anchors.centerIn: parent
                                    text: card.modelData.is_minimized ? "свёрнуто"
                                        : (card.modelData.monitor !== Theme.primaryMonitor ? card.modelData.monitor + " · " : "") + (card.modelData.tags[0] ?? "")
                                    color: Theme.text
                                    font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold; features: ({ "tnum": 1 }) }
                                }
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: 8
                            Image {
                                id: ico
                                anchors.verticalCenter: parent.verticalCenter
                                width: 26; height: 26
                                sourceSize { width: 52; height: 52 }
                                source: win.appIcon(card.modelData.appid)
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - ico.width - 8
                                Text {
                                    width: parent.width
                                    text: win.appName(card.modelData.appid)
                                    elide: Text.ElideRight
                                    color: Theme.text
                                    font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
                                }
                                // где окно: монитор · тег (+ «свёрнуто», «плавающее»)
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: (card.modelData.monitor + " · рабочий стол " + (card.modelData.tags[0] ?? "—"))
                                        + (card.modelData.is_minimized ? " · свёрнуто" : "")
                                        + (card.modelData.is_floating ? " · плавающее" : "")
                                        + (card.modelData.is_fullscreen ? " · на весь экран" : "")
                                    color: Theme.primary
                                    font { family: Theme.font; pixelSize: 11; weight: Font.Medium }
                                }
                                // что запущено в терминале
                                Text {
                                    readonly property var pr: Switcher.procs[String(card.modelData.pid)]
                                    visible: pr !== undefined
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: pr ? (pr.idle ? "терминал ожидает · " : "▶ " + pr.cmd + " · ") + pr.cwd : ""
                                    color: Theme.text
                                    font { family: Theme.font; pixelSize: 11 }
                                    layer.enabled: Session.privacy
                                    layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 48; saturation: -0.5 }
                                }
                                Text {
                                    width: parent.width
                                    text: card.modelData.title
                                    elide: Text.ElideRight
                                    color: Theme.muted
                                    font { family: Theme.font; pixelSize: 11 }
                                    layer.enabled: Session.privacy
                                    layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 48; saturation: -0.5; brightness: -0.05 }
                                }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: e => {
                            Switcher.index = card.index
                            if (e.button === Qt.MiddleButton) {
                                Quickshell.execDetached(["mmsg", "dispatch", "killclient", "client," + card.modelData.id])
                                Switcher.items = Switcher.items.filter(x => x !== card.modelData)
                            } else Switcher.commit()
                        }
                    }
                }
            }
        }
    }
}
