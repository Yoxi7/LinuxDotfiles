pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs

// Звук: слева устройства вывода, справа ввода — клик делает устройство основным; у основного громкость и mute.
// Ниже — громкость отдельных приложений. Открывается ПКМ по громкости в баре, из пункта управления или Super+… через modal toggle audio.
ModalWindow {
    id: root
    name: "audio"
    cardWidth: 940
    cardHeight: 700
    resizable: true
    minW: 700
    minH: 460

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var sources: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream)
    readonly property var streams: Pipewire.nodes.values.filter(n => n.audio && n.isStream && !n.isSink)
    PwObjectTracker { objects: root.sinks.concat(root.sources, root.streams) }

    // «Starship/Matisse HD Audio Controller Digital Stereo (HDMI)» → имя + хвост («Digital Stereo (HDMI)») мелким
    function parts(n) {
        const d = n?.description || n?.nickname || n?.name || "?"
        const m = /^(.*?)\s+((?:Digital|Analog|Pro|Multichannel|Mono|Stereo|Surround|Headset|Headphones|Speaker|Line|Microphone)\b.*)$/i.exec(d)
        return m ? [m[1], m[2]] : [d, ""]
    }
    function kind(n) {
        const s = ((n?.description ?? "") + " " + (n?.name ?? "")).toLowerCase()
        if (/bluez|bluetooth/.test(s)) return ""
        if (/hdmi|displayport|\bdp\b|hdmi-stereo/.test(s)) return ""
        if (/headset|headphone|hs[- ]?|наушник/.test(s)) return ""
        if (/usb/.test(s)) return ""
        if (/mic|микрофон|capture|input/.test(s) && !n?.isSink) return ""
        return n?.isSink ? "" : ""
    }
    function appName(n) { return n?.properties?.["application.name"] || n?.properties?.["node.name"] || n?.description || n?.name || "?" }

    // ── ползунок громкости
    component Slider: Item {
        id: sl
        property real value: 0
        property bool muted: false
        signal moved(real v)
        height: 22
        Rectangle {
            id: track
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            height: 8; radius: 4
            color: Theme.strong
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, sl.value / 1.5))
                height: parent.height; radius: 4
                color: sl.muted ? Theme.faint : sl.value > 1 ? Theme.danger : Theme.primary
            }
            // отметка 100%
            Rectangle { x: parent.width / 1.5 - 1; y: -3; width: 2; height: 14; radius: 1; color: Qt.rgba(1, 1, 1, 0.35) }
        }
        Rectangle {
            x: Math.max(0, Math.min(track.width, track.width * sl.value / 1.5)) - 8
            anchors.verticalCenter: parent.verticalCenter
            width: 16; height: 16; radius: 8
            color: Theme.text
            opacity: sm.containsMouse || sm.pressed ? 1 : 0.85
        }
        MouseArea {
            id: sm
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: e => sl.moved(Math.max(0, Math.min(1.5, e.x / width * 1.5)))
            onPositionChanged: e => { if (pressed) sl.moved(Math.max(0, Math.min(1.5, e.x / width * 1.5))) }
            onWheel: w => sl.moved(Math.max(0, Math.min(1.5, sl.value + (w.angleDelta.y > 0 ? 0.05 : -0.05))))
        }
    }

    // ── строка устройства
    component Device: Rectangle {
        id: dev
        property var node
        property bool isDefault: false
        property bool markable: false
        signal picked
        signal hint(var item, string text)
        width: parent?.width ?? 0
        height: 56; radius: 12
        color: isDefault ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16) : dm.containsMouse ? Theme.strong : Theme.weak
        border { width: isDefault ? 1 : 0; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55) }
        Behavior on color { ColorAnimation { duration: Theme.dFast } }
        readonly property var p: root.parts(node)
        Text {
            id: ic
            x: 14; anchors.verticalCenter: parent.verticalCenter
            text: root.kind(dev.node)
            color: dev.isDefault ? Theme.primary : Theme.muted
            font { family: Theme.iconFont; pixelSize: 18 }
            width: 24; horizontalAlignment: Text.AlignHCenter
        }
        Column {
            anchors { left: ic.right; leftMargin: 12; right: mark.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 2
            Text { width: parent.width; elide: Text.ElideRight; text: dev.p[0]; color: Theme.text; font { family: Theme.font; pixelSize: 13; weight: dev.isDefault ? Font.DemiBold : Font.Medium } }
            Text { visible: dev.p[1] !== ""; width: parent.width; elide: Text.ElideRight; text: dev.p[1]; color: Theme.faint; font { family: Theme.font; pixelSize: 11 } }
        }
        Text {
            id: mark
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            text: dev.isDefault ? "" : ""
            color: Theme.primary
            font { family: Theme.iconFont; pixelSize: 14 }
        }
        MouseArea { id: dm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dev.picked() }
    }

    // ── колонка «Вывод» / «Ввод»
    component Section: Item {
        id: sec
        property string title
        property string icon
        property var nodes: []
        property var current: null
        property bool markable: false
        signal pick(var node)
        readonly property var audio: current?.audio ?? null
        Row {
            id: head
            spacing: 10
            Text { anchors.verticalCenter: parent.verticalCenter; text: sec.icon; color: Theme.primary; font { family: Theme.iconFont; pixelSize: 18 } }
            Text { anchors.verticalCenter: parent.verticalCenter; text: sec.title; color: Theme.text; font { family: Theme.font; pixelSize: 17; weight: Font.DemiBold } }
        }
        // громкость основного устройства
        Rectangle {
            id: vol
            anchors { left: parent.left; right: parent.right; top: head.bottom; topMargin: 12 }
            height: 62; radius: 14
            color: Qt.rgba(0, 0, 0, 0.22)
            Rectangle {
                id: muteBtn
                x: 12; anchors.verticalCenter: parent.verticalCenter
                width: 36; height: 36; radius: 18
                color: mm.containsMouse ? Theme.strong : Theme.weak
                Text {
                    anchors.centerIn: parent
                    text: sec.audio?.muted ? (sec.icon === "" ? "" : "") : sec.icon
                    color: sec.audio?.muted ? Theme.danger : Theme.text
                    font { family: Theme.iconFont; pixelSize: 15 }
                }
                MouseArea { id: mm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (sec.audio) sec.audio.muted = !sec.audio.muted }
            }
            Slider {
                anchors { left: muteBtn.right; leftMargin: 14; right: pct.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                value: sec.audio?.volume ?? 0
                muted: sec.audio?.muted ?? false
                onMoved: v => { if (sec.audio) sec.audio.volume = v }
            }
            Text {
                id: pct
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                width: 44; horizontalAlignment: Text.AlignRight
                text: sec.audio?.muted ? "выкл" : Math.round((sec.audio?.volume ?? 0) * 100) + "%"
                color: sec.audio?.muted ? Theme.danger : Theme.text
                font { family: Theme.font; pixelSize: 13; weight: Font.Medium; features: ({ "tnum": 1 }) }
            }
        }
        Text {
            id: lbl
            anchors { left: parent.left; top: vol.bottom; topMargin: 14 }
            text: "УСТРОЙСТВА"
            color: Theme.faint
            font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold; letterSpacing: 0.6 }
        }
        Flickable {
            anchors { left: parent.left; right: parent.right; top: lbl.bottom; bottom: parent.bottom; topMargin: 8 }
            contentHeight: devCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: devCol
                width: parent.width
                spacing: 6
                Repeater {
                    model: sec.nodes
                    Device {
                        required property var modelData
                        node: modelData
                        isDefault: modelData === sec.current
                        markable: sec.markable
                        onPicked: sec.pick(modelData)
                        onHint: (item, text) => root.tipRequest(item, text)
                    }
                }
                Text { visible: sec.nodes.length === 0; text: "Устройств нет"; color: Theme.muted; font { family: Theme.font; pixelSize: 13 } }
            }
        }
    }

    Item {
        anchors { fill: parent; margins: 22 }

        Text {
            id: title
            text: "Звук"
            color: Theme.text
            font { family: Theme.font; pixelSize: 20; weight: Font.DemiBold }
        }
        Text {
            anchors { left: title.right; leftMargin: 12; verticalCenter: title.verticalCenter }
            text: "клик по устройству делает его основным"
            color: Theme.faint
            font { family: Theme.font; pixelSize: 12 }
        }

        // наушники ⇄ колонки: переключение по кругу между отмеченными устройствами
        Rectangle {
            anchors { right: parent.right; verticalCenter: title.verticalCenter }
            height: 34; radius: 17
            width: swapRow.implicitWidth + 28
            color: swapM.containsMouse ? Theme.strong : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
            border { width: 1; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.6) }
            opacity: AudioTools.available ? 1 : 0.5
            Behavior on color { ColorAnimation { duration: Theme.dFast } }
            Row {
                id: swapRow
                anchors.centerIn: parent
                spacing: 8
                Text { anchors.verticalCenter: parent.verticalCenter; text: "\uf0ec"; color: Theme.primary; font { family: Theme.iconFont; pixelSize: 13 } }
                Text { anchors.verticalCenter: parent.verticalCenter; text: AudioTools.available ? "Переключить на: " + root.parts(AudioTools.next)[0] : "Отметьте ⇄ два устройства вывода"; color: Theme.text; font { family: Theme.font; pixelSize: 13; weight: Font.Medium } }
            }
            MouseArea { id: swapM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: AudioTools.swap() }
        }

        Section {
            id: outSec
            anchors { left: parent.left; top: title.bottom; topMargin: 18; bottom: cyc.top; bottomMargin: 16 }
            width: (parent.width - 24) / 2
            title: "Вывод"
            icon: ""
            nodes: root.sinks
            current: root.sink
            markable: true
            onPick: n => Pipewire.preferredDefaultAudioSink = n
        }
        Section {
            id: inSec
            anchors { right: parent.right; top: title.bottom; topMargin: 18; bottom: cyc.top; bottomMargin: 16 }
            width: (parent.width - 24) / 2
            title: "Ввод"
            icon: ""
            nodes: root.sources
            current: root.source
            onPick: n => Pipewire.preferredDefaultAudioSource = n
        }

        // быстрое переключение: какие устройства вывода чередует кнопка в баре
        Rectangle {
            id: cyc
            anchors { left: parent.left; right: parent.right; bottom: apps.top; bottomMargin: apps.visible ? 14 : 0 }
            height: cycCol.implicitHeight + 24
            radius: 14
            color: Qt.rgba(0, 0, 0, 0.22)
            Column {
                id: cycCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 8
                Row {
                    spacing: 10
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "\uf0ec"; color: Theme.primary; font { family: Theme.iconFont; pixelSize: 14 } }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Быстрое переключение"; color: Theme.text; font { family: Theme.font; pixelSize: 14; weight: Font.DemiBold } }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "— отметьте устройства, между которыми переключает кнопка в баре"; color: Theme.faint; font { family: Theme.font; pixelSize: 12 } }
                }
                Flow {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: root.sinks
                        Rectangle {
                            id: opt
                            required property var modelData
                            readonly property bool on: AudioTools.isMarked(modelData)
                            height: 36; width: ol.implicitWidth + 58; radius: 18
                            color: on ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.22) : om.containsMouse ? Theme.strong : Theme.weak
                            border { width: 1; color: on ? Theme.primary : "transparent" }
                            Behavior on color { ColorAnimation { duration: Theme.dFast } }
                            Rectangle {
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                width: 18; height: 18; radius: 5
                                color: opt.on ? Theme.primary : "transparent"
                                border { width: 2; color: opt.on ? Theme.primary : Theme.faint }
                                Text { anchors.centerIn: parent; visible: opt.on; text: "\uf00c"; color: Theme.base; font { family: Theme.iconFont; pixelSize: 10 } }
                            }
                            Text { id: ol; x: 40; anchors.verticalCenter: parent.verticalCenter; text: root.parts(opt.modelData)[0]; color: Theme.text; font { family: Theme.font; pixelSize: 13; weight: opt.on ? Font.DemiBold : Font.Medium } }
                            MouseArea { id: om; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: AudioTools.toggleMark(opt.modelData) }
                        }
                    }
                }
                Text {
                    visible: !AudioTools.available
                    text: "Отметьте минимум два устройства — иначе кнопка переключает по всем."
                    color: Theme.muted
                    font { family: Theme.font; pixelSize: 12 }
                }
            }
        }

        // приложения
        Item {
            id: apps
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: root.streams.length === 0 ? 0 : Math.min(190, appCol.implicitHeight + 30)
            visible: height > 0
            Text { id: appHead; text: "ПРИЛОЖЕНИЯ"; color: Theme.faint; font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold; letterSpacing: 0.6 } }
            Flickable {
                anchors { left: parent.left; right: parent.right; top: appHead.bottom; bottom: parent.bottom; topMargin: 8 }
                contentHeight: appCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: appCol
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: root.streams
                        Item {
                            required property var modelData
                            width: appCol.width; height: 30
                            Text { x: 0; width: 170; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: root.appName(parent.modelData); color: Theme.text; font { family: Theme.font; pixelSize: 13 } }
                            Slider {
                                anchors { left: parent.left; leftMargin: 190; right: ap.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                value: parent.modelData.audio?.volume ?? 0
                                muted: parent.modelData.audio?.muted ?? false
                                onMoved: v => { if (parent.modelData.audio) parent.modelData.audio.volume = v }
                            }
                            Text { id: ap; anchors { right: parent.right; verticalCenter: parent.verticalCenter } width: 44; horizontalAlignment: Text.AlignRight; text: Math.round((parent.modelData.audio?.volume ?? 0) * 100) + "%"; color: Theme.muted; font { family: Theme.font; pixelSize: 12; features: ({ "tnum": 1 }) } }
                        }
                    }
                }
            }
        }
    }
}
