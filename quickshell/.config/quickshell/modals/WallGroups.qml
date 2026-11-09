pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Quickshell
import qs

// Группы обоев: что показывать, на каких мониторах, как часто и в каком порядке. Меняются сами по таймеру.
// Папки и файлы добавляются из пикера обоев (кнопка «в группу» на плитке и на панели).
ModalWindow {
    id: root
    name: "wallgroups"
    cardWidth: 780
    resizable: true
    minW: 560
    minH: 420
    cardHeight: 760
    captureEscape: renaming
    property bool renaming: false

    readonly property var screenNames: Quickshell.screens.map(s => s.name)
    function ago(g) {
        const s = WallGroups.secondsLeft(g)
        return s < 60 ? "меньше минуты" : s < 3600 ? Math.round(s / 60) + " мин" : Math.floor(s / 3600) + " ч " + Math.round(s % 3600 / 60) + " мин"
    }
    function leaf(p) { return p.slice(p.lastIndexOf("/") + 1) || p }
    property int tick: 0
    Timer { interval: 10000; running: true; repeat: true; onTriggered: root.tick++ }

    // подсказки при наведении
    property Item tipItem: null
    property Item tipPending: null
    property string tipText: ""
    function tipRequest(item, text) {
        if (item === null) { tipPending = null; tipTimer.stop(); tipItem = null; return }
        tipPending = item; tipText = text; tipTimer.restart()
    }
    Timer { id: tipTimer; interval: 350; onTriggered: root.tipItem = root.tipPending }
    Rectangle {
        z: 100
        parent: root.card
        visible: root.tipItem !== null && root.tipText !== ""
        readonly property point pos: root.tipItem ? root.tipItem.mapToItem(root.card, 0, 0) : Qt.point(0, 0)
        width: Math.min(300, tipLabel.implicitWidth + 20)
        height: tipLabel.implicitHeight + 14
        x: Math.max(6, Math.min(root.card.width - width - 6, pos.x + (root.tipItem ? root.tipItem.width / 2 : 0) - width / 2))
        y: pos.y + (root.tipItem ? root.tipItem.height : 0) + 8 + height > root.card.height ? pos.y - height - 8 : pos.y + (root.tipItem ? root.tipItem.height : 0) + 8
        radius: 10
        color: Qt.rgba(0.04, 0.04, 0.06, 0.96)
        border { width: 1; color: Qt.rgba(1, 1, 1, 0.14) }
        Text { id: tipLabel; x: 10; y: 7; width: Math.min(280, implicitWidth); text: root.tipText; wrapMode: Text.Wrap; color: Theme.text; font { family: Theme.font; pixelSize: 12 } }
    }

    component Chip: Rectangle {
        id: chip
        property string label
        property bool on: false
        property string tip: ""
        signal clicked
        height: 28; width: cl.implicitWidth + 22; radius: 14
        color: on ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.28) : cm.containsMouse ? Theme.strong : Theme.weak
        border { width: on ? 1 : 0; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.7) }
        Behavior on color { ColorAnimation { duration: Theme.dFast } }
        Text { id: cl; anchors.centerIn: parent; text: chip.label; color: Theme.text; font { family: Theme.font; pixelSize: 12; weight: chip.on ? Font.DemiBold : Font.Medium } }
        MouseArea {
            id: cm
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (chip.tip !== "") root.tipRequest(containsMouse ? chip : null, chip.tip)
            onClicked: { root.tipRequest(null, ""); chip.clicked() }
        }
    }

    // ── перетаскивание за верхнюю полосу (двойной клик — на место; на другой монитор — тоже)
    MouseArea {
        id: dragArea
        z: -1
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 64
        property real sx: 0
        property real sy: 0
        property real ox: 0
        property real oy: 0
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        onPressed: e => { const p = mapToItem(null, e.x, e.y); sx = p.x; sy = p.y; ox = root.offX; oy = root.offY }
        onPositionChanged: e => {
            if (!pressed) return
            const p = mapToItem(null, e.x, e.y)
            root.offX = ox + p.x - sx
            root.offY = oy + p.y - sy
        }
        onDoubleClicked: { root.offX = 0; root.offY = 0 }
        onReleased: e => {
            const scr = root.screen
            const p = mapToItem(null, e.x, e.y)
            const gx = scr.x + p.x, gy = scr.y + p.y
            const t = Quickshell.screens.find(c => gx >= c.x && gx < c.x + c.width && gy >= c.y && gy < c.y + c.height)
            if (!t || t.name === scr.name) return
            Modal.anchorScreen = t
            root.offX = (gx - t.x) - t.width / 2
            root.offY = (gy - t.y) - t.height / 2 + root.card.height / 2 - 28
        }
    }

    Item {
        anchors { fill: parent; margins: 20 }

        Text {
            id: title
            text: "Группы обоев"
            color: Theme.text
            font { family: Theme.font; pixelSize: 20; weight: Font.DemiBold }
        }
        Text {
            anchors { left: title.right; leftMargin: 12; verticalCenter: title.verticalCenter }
            text: "меняются сами, пока запущена оболочка"
            color: Theme.faint
            font { family: Theme.font; pixelSize: 12 }
        }
        Chip {
            id: prevChip
            anchors { right: newChip.left; rightMargin: 6; verticalCenter: title.verticalCenter }
            label: "Превью"
            on: Session.wgPreviews
            tip: Session.wgPreviews ? "Скрыть превью обоев (легче и короче список)" : "Показать превью обоев"
            onClicked: Session.wgPreviews = !Session.wgPreviews
        }
        Chip { id: newChip; anchors { right: parent.right; verticalCenter: title.verticalCenter } label: "＋ Новая группа"; tip: "Создать пустую группу: папки и файлы добавляются из пикера обоев, а монитору группа выбирается в списке «Мониторы»"; on: true; onClicked: WallGroups.create("", [], []) }

        Flickable {
            id: flick
            anchors { left: parent.left; right: parent.right; top: title.bottom; bottom: parent.bottom; topMargin: 16 }
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 4000
            maximumFlickVelocity: 6000
            // колесо: шаг по 90 px с плавным доездом (стандартный шаг Flickable — крошечный и рваный)
            property real targetY: 0
            onContentYChanged: if (!scrollAnim.running && !dragging && !flicking) targetY = contentY
            NumberAnimation { id: scrollAnim; target: flick; property: "contentY"; duration: 140; easing.type: Easing.OutCubic }
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: e => {
                    const max = Math.max(0, flick.contentHeight - flick.height)
                    flick.targetY = Math.max(0, Math.min(max, flick.targetY - e.angleDelta.y * 0.75))
                    scrollAnim.stop(); scrollAnim.to = flick.targetY; scrollAnim.from = flick.contentY; scrollAnim.start()
                }
            }
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 6 }

            Column {
                id: col
                width: parent.width
                spacing: 12

                // ── мониторы: каждому — своя группа
                Text { text: "Мониторы"; color: Theme.text; font { family: Theme.font; pixelSize: 15; weight: Font.DemiBold } }
                Repeater {
                    model: Quickshell.screens
                    Rectangle {
                        id: mrow
                        required property var modelData
                        readonly property string cur: WallGroups.assign[modelData.name] ?? ""
                        width: col.width
                        height: mcol.implicitHeight + 24
                        radius: 14
                        color: Qt.rgba(1, 1, 1, 0.04)
                        border { width: 1; color: Qt.rgba(1, 1, 1, 0.08) }
                        Column {
                            id: mcol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 8
                            Row {
                                spacing: 10
                                Text { text: mrow.modelData.name; color: Theme.text; font { family: Theme.font; pixelSize: 14; weight: Font.DemiBold } }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: mrow.modelData.width + "×" + mrow.modelData.height; color: Theme.faint; font { family: Theme.font; pixelSize: 12 } }
                            }
                            Flow {
                                width: parent.width; spacing: 4
                                Chip { label: "Без группы"; tip: "Этот монитор не участвует в автосмене: обои на нём меняются только вручную"; on: mrow.cur === ""; onClicked: WallGroups.setMonitor(mrow.modelData.name, "") }
                                Repeater {
                                    model: WallGroups.groups
                                    Chip {
                                        required property var modelData
                                        label: modelData.name
                                        tip: "На этом мониторе обои меняет группа «" + modelData.name + "»"
                                        on: mrow.cur === modelData.id
                                        onClicked: WallGroups.setMonitor(mrow.modelData.name, modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }
                Text { topPadding: 6; text: "Группы"; color: Theme.text; font { family: Theme.font; pixelSize: 15; weight: Font.DemiBold } }

                Text {
                    visible: WallGroups.groups.length === 0
                    width: parent.width
                    topPadding: 60
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: "Групп пока нет.\nСоздайте группу и добавьте в неё папки или файлы кнопкой «в группу» в пикере обоев."
                    color: Theme.muted
                    font { family: Theme.font; pixelSize: 14 }
                }

                Repeater {
                    model: WallGroups.groups
                    Rectangle {
                        id: card
                        required property var modelData
                        readonly property var g: modelData
                        width: col.width
                        height: gcol.implicitHeight + 28
                        radius: 16
                        color: Qt.rgba(1, 1, 1, 0.04)
                        border { width: 1; color: Qt.rgba(1, 1, 1, 0.08) }

                        Column {
                            id: gcol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                            spacing: 10

                            // имя · следующая смена · вкл · удалить
                            Item {
                                width: parent.width; height: 32
                                Rectangle {
                                    id: nameBox
                                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                    width: 230; height: 32; radius: 9
                                    color: nameIn.activeFocus ? Theme.strong : nameHover.hovered ? Theme.weak : "transparent"
                                    border { width: nameIn.activeFocus ? 1 : 0; color: Theme.primary }
                                    HoverHandler { id: nameHover; cursorShape: Qt.IBeamCursor }
                                    TextInput {
                                        id: nameIn
                                        anchors { fill: parent; leftMargin: 10; rightMargin: 28 }
                                        verticalAlignment: TextInput.AlignVCenter
                                        text: card.g.name
                                        color: Theme.text
                                        font { family: Theme.font; pixelSize: 16; weight: Font.DemiBold }
                                        selectByMouse: true
                                        clip: true
                                        function commit() { if (text.trim() !== "" && text.trim() !== card.g.name) WallGroups.patch(card.g.id, { name: text.trim() }); else text = card.g.name }
                                        onAccepted: { commit(); focus = false }
                                        onActiveFocusChanged: { root.renaming = activeFocus; if (!activeFocus) commit() }
                                        Keys.onEscapePressed: e => { text = card.g.name; focus = false; e.accepted = true }
                                    }
                                    Text {
                                        anchors { right: parent.right; rightMargin: 9; verticalCenter: parent.verticalCenter }
                                        text: "\uf040"
                                        color: nameHover.hovered || nameIn.activeFocus ? Theme.muted : Theme.faint
                                        font { family: Theme.iconFont; pixelSize: 12 }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        visible: !nameIn.activeFocus
                                        cursorShape: Qt.IBeamCursor
                                        onClicked: { nameIn.forceActiveFocus(); nameIn.selectAll() }
                                        onContainsMouseChanged: root.tipRequest(containsMouse ? nameBox : null, "Переименовать группу")
                                    }
                                }
                                Row {
                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                    spacing: 6
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: card.g.enabled && card.g.sources.length > 0
                                        text: { root.tick; return "следующая через " + root.ago(card.g) }
                                        color: Theme.faint
                                        font { family: Theme.font; pixelSize: 12 }
                                    }
                                    Chip { tip: "Поменять обои этой группы прямо сейчас"; label: "Сменить сейчас"; onClicked: WallGroups.rotate(card.g.id) }
                                    Chip { tip: "Включить или выключить автосмену для этой группы"; label: card.g.enabled ? "Включена" : "Выключена"; on: card.g.enabled; onClicked: WallGroups.patch(card.g.id, { enabled: !card.g.enabled }) }
                                    Chip { tip: "Удалить группу (сами картинки остаются на месте)"; label: "Удалить"; onClicked: WallGroups.remove(card.g.id) }
                                }
                            }

                            // мониторы этой группы (выбираются в списке мониторов выше)
                            Text {
                                width: parent.width
                                wrapMode: Text.Wrap
                                text: { const m = WallGroups.monitorsOf(card.g.id); return m.length ? "Мониторы: " + m.join(", ") : "Ни один монитор не выбрал эту группу — она не меняет обои" }
                                color: WallGroups.monitorsOf(card.g.id).length ? Theme.muted : Theme.faint
                                font { family: Theme.font; pixelSize: 12 }
                            }
                            // как часто
                            Flow {
                                width: parent.width; spacing: 4
                                Text { height: 28; verticalAlignment: Text.AlignVCenter; rightPadding: 6; text: "Менять раз в"; color: Theme.faint; font { family: Theme.font; pixelSize: 12 } }
                                Repeater {
                                    model: WallGroups.intervals
                                    Chip {
                                        required property var modelData
                                        label: modelData.label
                                        tip: "Как часто менять обои"
                                        on: card.g.interval === modelData.m
                                        onClicked: WallGroups.patch(card.g.id, { interval: modelData.m })
                                    }
                                }
                            }
                            // порядок
                            Flow {
                                width: parent.width; spacing: 4
                                Text { height: 28; verticalAlignment: Text.AlignVCenter; rightPadding: 6; text: "Порядок"; color: Theme.faint; font { family: Theme.font; pixelSize: 12 } }
                                Repeater {
                                    model: WallGroups.orders
                                    Chip {
                                        required property var modelData
                                        label: modelData.label
                                        tip: modelData.id === "random" ? "Случайная картинка, не повторяя предыдущую" : modelData.id === "name" ? "По очереди, по алфавиту, по кругу" : "По очереди, от новых файлов к старым"
                                        on: card.g.order === modelData.id
                                        onClicked: WallGroups.patch(card.g.id, { order: modelData.id })
                                    }
                                }
                            }
                            // источники
                            Column {
                                width: parent.width
                                spacing: 4
                                Text {
                                    visible: card.g.sources.length === 0
                                    text: "Пусто: добавьте папку или файлы из пикера обоев"
                                    color: Theme.muted
                                    font { family: Theme.font; pixelSize: 12 }
                                }
                                Repeater {
                                    model: card.g.sources
                                    Column {
                                        id: src
                                        required property string modelData
                                        readonly property bool isFile: /\.(jpe?g|png|webp|avif|bmp|gif)$/i.test(modelData)
                                        width: gcol.width
                                        spacing: 6
                                        Item {
                                            width: parent.width; height: 26
                                            Text {
                                                anchors { left: parent.left; right: del.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                                elide: Text.ElideMiddle
                                                text: (src.isFile ? "\uf03e  " : "\uf07b  ") + src.modelData.replace(Quickshell.env("HOME"), "~") + (src.isFile ? "" : "   ·   " + fl.count + " шт.")
                                                color: Theme.text
                                                font { family: Theme.font; pixelSize: 12; weight: Font.Medium }
                                            }
                                            Text {
                                                id: del
                                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                                text: "\uf00d"
                                                color: dm.containsMouse ? Theme.danger : Theme.muted
                                                font { family: Theme.iconFont; pixelSize: 12 }
                                                MouseArea {
                                                    id: dm
                                                    anchors.fill: parent
                                                    anchors.margins: -6
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onContainsMouseChanged: root.tipRequest(containsMouse ? del : null, "Убрать из группы")
                                                    onClicked: WallGroups.removeSource(card.g.id, src.modelData)
                                                }
                                            }
                                        }
                                        FolderListModel {
                                            id: fl
                                            folder: src.isFile ? "" : "file://" + src.modelData
                                            nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.avif", "*.bmp", "*.gif"]
                                            caseSensitive: false
                                            showDirs: false
                                            sortField: FolderListModel.Time
                                            sortReversed: true
                                        }
                                        // превью: клик по картинке ставит её на мониторы группы
                                        Flow {
                                            visible: Session.wgPreviews
                                            width: parent.width
                                            spacing: 6
                                            Repeater {
                                                model: Session.wgPreviews ? (src.isFile ? [src.modelData] : Math.min(fl.count, 18)) : 0
                                                Rectangle {
                                                    id: th
                                                    required property var modelData
                                                    required property int index
                                                    readonly property string path: src.isFile ? modelData : fl.get(index, "filePath")
                                                    readonly property bool current: path === card.g.last
                                                    width: 132; height: 78; radius: 8
                                                    color: Theme.weak
                                                    clip: true
                                                    border { width: current ? 2 : 0; color: Theme.primary }
                                                    Image {
                                                        anchors.fill: parent
                                                        source: th.path ? "file://" + th.path : ""
                                                        sourceSize { width: 264; height: 156 }
                                                        fillMode: Image.PreserveAspectCrop
                                                        asynchronous: true
                                                        cache: false
                                                        opacity: thm.containsMouse ? 1 : 0.9
                                                    }
                                                    Rectangle {
                                                        visible: th.current
                                                        anchors { left: parent.left; bottom: parent.bottom; margins: 4 }
                                                        height: 16; width: curT.implicitWidth + 10; radius: 8
                                                        color: Qt.rgba(0, 0, 0, 0.7)
                                                        Text { id: curT; anchors.centerIn: parent; text: "сейчас"; color: Theme.text; font { family: Theme.font; pixelSize: 10 } }
                                                    }
                                                    MouseArea {
                                                        id: thm
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onContainsMouseChanged: root.tipRequest(containsMouse ? th : null, "Поставить на мониторы группы")
                                                        onClicked: WallGroups.applyNow(card.g.id, th.path)
                                                    }
                                                }
                                            }
                                            Text {
                                                visible: Session.wgPreviews && !src.isFile && fl.count > 18
                                                height: 78
                                                verticalAlignment: Text.AlignVCenter
                                                leftPadding: 6
                                                text: "ещё " + (fl.count - 18)
                                                color: Theme.faint
                                                font { family: Theme.font; pixelSize: 12 }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
