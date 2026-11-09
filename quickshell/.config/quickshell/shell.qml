import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import "bar"

// Лёгкая оболочка вместо ashell. В памяти постоянно живут только бар и сервисы
// (уведомления, OSD-наблюдатель). Все окна создаются по вызову и уничтожаются при закрытии:
//   qs -c lite ipc call modal toggle launcher|wallpapers|power|cheatsheet|control|notifications|weather|clipboard|system|player|calendar
//   qs -c lite ipc call modal close
//   qs -c lite ipc call bar state | click <виджет> <кнопка> <монитор> | tray <цель> <кнопка> <монитор> | add|remove|move|join|setZone|reset
//   qs -c lite ipc call audio volumeUp|volumeDown|toggleMute|toggleMicMute|setVolume|setMicVolume|state
//   qs -c lite ipc call player state|toggle|next|previous|like|seek|setVolume
//   qs -c lite ipc call organizer state|todoAdd|todoToggle|todoRemove|todoFocus|todoClearDone|pomodoroStart|pomodoroStop
//   qs -c lite ipc call weather state|refresh
//   qs -c lite ipc call display state|setBrightness|nightLight|caffeine
//   qs -c lite ipc call notifications toggleDnd|clear|dismissApp|dismissId|state
//   qs -c lite ipc call osd player
//   qs -c lite ipc call cooling status | profile <имя>
//   qs -c lite ipc call modal toggle overview                       — обзор тегов
//   qs -c lite ipc call modal toggle emoji                          — эмодзи
//   qs -c lite ipc call switcher next|prev|commit|cancel            — Alt+Tab
//   qs -c lite ipc call region screenshot|menu|edit|ocr|record|recordSound|dismiss|state
ShellRoot {
    Component.onCompleted: { WallGroups.groups; Tuya.refresh(); ObsNow.key; blurApply.running = true }        // поднять таймеры групп обоев; применить блюр
    // блюр: правило слоёв оболочки и общий блюр окон (терминал, Discord…) включаются и выключаются на лету
    Process {
        id: blurApply
        command: Mango.isMango
            ? ["mmsg", "dispatch", "setoption,blur," + (Session.blurOff ? "0" : "1")]
            : ["sh", "-c", "command -v hyprctl >/dev/null && hyprctl eval 'hl.config({ decoration = { blur = { enabled = " + (Session.blurOff ? "false" : "true") + " } } })' || true"]
    }
    Connections { target: Session; function onBlurOffChanged() { blurApply.running = true } }
    // сервисы: агент polkit, простой (экран / блокировка), сокет для скриптов, виджеты рабочего стола
    PolkitUi { id: polkitUi }
    IdleGuard { id: idleGuard }
    SocketBus {}
    DeskWidgets {}
    MiniDash {}

    IpcHandler {
        target: "bar"
        function state(): string {
            const top = ToplevelManager.activeToplevel
            const periphs = []
            const up = UPower.devices.values
            for (let i = 0; i < up.length; i++) {
                const d = up[i]
                if (d.powerSupply || d.isLaptopBattery || !d.isPresent || d.percentage <= 0) continue
                periphs.push({ model: d.model || "Устройство", type: UPowerDeviceType.toString(d.type), percent: Math.round(d.percentage * 100) })
            }
            const trayItems = []
            const tr = SystemTray.items.values
            for (let i = 0; i < tr.length; i++) {
                const it = tr[i]
                trayItems.push({ index: i, id: it.id ?? "", title: it.title ?? "", tooltip: it.tooltipTitle ?? "", hasMenu: !!it.hasMenu, onlyMenu: !!it.onlyMenu })
            }
            const btDevs = (Bluetooth.defaultAdapter?.devices?.values ?? []).filter(d => d.connected).map(d => ({
                name: d.name, battery: d.batteryAvailable ? Math.round(d.battery * 100) : null
            }))
            const sink = Pipewire.defaultAudioSink
            const source = Pipewire.defaultAudioSource
            const mons = Quickshell.screens.map(s => ({
                name: s.name,
                scope: s.name === Theme.primaryMonitor ? "primary" : "secondary",
                workspace: Mango.monitors[s.name]?.tag ?? 1,
                layout: Mango.monitors[s.name]?.layout ?? "",
                layoutSymbol: Mango.monitors[s.name]?.symbol ?? "",
                windowCount: Mango.monitors[s.name]?.count ?? 0,
                workspaceCounts: Mango.monitors[s.name]?.counts ?? []
            }))
            return JSON.stringify({
                monitors: mons,
                layout: BarLayout.layout,
                islands: {
                    primary: { left: BarLayout.islands("primary", "left"), center: BarLayout.islands("primary", "center"), right: BarLayout.islands("primary", "right") },
                    secondary: { left: BarLayout.islands("secondary", "left"), center: BarLayout.islands("secondary", "center"), right: BarLayout.islands("secondary", "right") }
                },
                hidden: {
                    primary: BarLayout.pool("primary").map(c => c.id),
                    secondary: BarLayout.pool("secondary").map(c => c.id)
                },
                catalog: BarLayout.catalog.map(c => ({ id: c.id, label: c.label, note: c.note })),
                widgets: {
                    title: { title: top?.title ?? "", appId: top?.appId ?? "" },
                    clock: Qt.formatDateTime(new Date(), "ddd, d MMM · HH:mm:ss"),
                    kbd: { short: Mango.layoutShort, name: Mango.layoutName, raw: Mango.layout },
                    recording: { active: Shot.recording, elapsedSec: Shot.recording ? Math.round((Date.now() - Shot.recordStart) / 1000) : 0 },
                    pomodoro: { running: Pomodoro.running, label: Pomodoro.label, remainingSec: Pomodoro.remaining, task: Pomodoro.task },
                    weather: { loaded: Weather.loaded, city: Weather.city, temp: Weather.temp, feelsLike: Weather.feelsLike, description: Weather.description, wind: Weather.wind, humidity: Weather.humidity, pressure: Weather.pressure, todayMax: Weather.todayMax, todayMin: Weather.todayMin, sources: Weather.sources },
                    media: { available: Player.available, playing: Player.playing, player: Player.playerName, label: Player.label, title: Player.title, artist: Player.artist, album: Player.album, position: Math.round(Player.livePosition), duration: Math.round(Player.duration), volume: Math.round(Player.volume * 100), liked: Player.liked },
                    stats: { cpuLoad: Cooling.available ? Math.round(Cooling.cpuLoad) : SysInfo.cpu, cpuTemp: Cooling.available ? Math.round(Cooling.cpuTemp) : SysInfo.temp, gpuLoad: Math.round(Cooling.gpuLoad), gpuTemp: Math.round(Cooling.gpuTemp), ramPercent: SysInfo.mem, ramUsedGiB: Number(SysInfo.memUsed.toFixed(1)), ramTotalGiB: Number(SysInfo.memTotal.toFixed(1)) },
                    periph: periphs,
                    net: { wired: Net.wired?.name ?? null, wifi: Net.wifi?.name ?? null, vpns: Net.vpns.map(v => v.name), active: Net.active },
                    ai: { busy: Ai.busy, unread: Ai.unread, provider: Ai.provider, model: Ai.model, effort: Ai.effort, agent: Ai.agent },
                    tray: trayItems,
                    bell: { count: Notifs.count, dnd: Session.dnd, gaming: Notifs.gaming },
                    status: {
                        privacyMode: Session.privacy,
                        privacyStreams: { mic: Privacy.mic, screen: Privacy.screen, camera: Privacy.camera },
                        idleInhibit: Session.idleInhibit,
                        nightLight: Session.nightLight,
                        nightTemp: Session.nightTemp,
                        bluetooth: btDevs,
                        micMuted: source?.audio?.muted ?? false,
                        micVolume: Math.round((source?.audio?.volume ?? 0) * 100),
                        sinkName: sink?.description ?? "",
                        sinkMuted: sink?.audio?.muted ?? false,
                        sinkVolume: Math.round((sink?.audio?.volume ?? 0) * 100)
                    }
                }
            })
        }
        function click(widget: string, button: string, screen: string): string {
            const w = widget.trim().toLowerCase()
            const b = (button || "left").trim().toLowerCase()
            const scrName = (screen || Theme.primaryMonitor).trim()
            const scrObj = Quickshell.screens.find(s => s.name === scrName) ?? Theme.primaryScreen()
            const openPop = (modalName, anchorWidget) => {
                const x = BarLayout.widgetCenterX(scrObj.name, anchorWidget || w)
                if (x >= 0) Modal.toggleAt(modalName, x, scrObj)
                else Modal.openOn(modalName, scrObj.name)
                return "ok: открыто/переключено окно «" + modalName + "» на " + scrObj.name + (x >= 0 ? " (x=" + Math.round(x) + ")" : "")
            }
            switch (w) {
            case "kbd":
            case "keyboard":
                Mango.switchLayout()
                return "ok: переключена раскладка клавиатуры"
            case "tags":
            case "workspaces": {
                if (/^\d+$/.test(b)) {
                    const n = Math.max(1, Math.min(10, parseInt(b)))
                    Mango.view(scrObj.name, n)
                    return "ok: рабочий стол " + n + " на " + scrObj.name
                }
                if (b === "up" || b === "prev" || b === "down" || b === "next") {
                    const cur = Mango.monitors[scrObj.name]?.tag ?? 1
                    const nxt = Math.max(1, Math.min(10, cur + (b === "up" || b === "prev" ? -1 : 1)))
                    Mango.view(scrObj.name, nxt)
                    return "ok: рабочий стол " + nxt + " на " + scrObj.name
                }
                return openPop("overview", "tags")
            }
            case "layout": {
                const cmd = b === "right" ? "setlayout,tile"
                          : (b === "left" || b === "up" || b === "down" || b === "next") ? "switch_layout"
                          : "setlayout," + b
                Quickshell.execDetached(["bash", "-c", 'mmsg dispatch "focusmon,$1" >/dev/null; mmsg dispatch "$2"', "lay", scrObj.name, cmd])
                return "ok: раскладка окон (" + cmd + ") на " + scrObj.name
            }
            case "title": return openPop("wininfo", "title")
            case "launcher": return openPop(b === "right" ? "overview" : "launcher", "launcher")
            case "clock": return openPop("calendar", "clock")
            case "recording":
                if (Shot.recording) {
                    Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/qs-record", "--stop"])
                    return "ok: запись экрана остановлена"
                }
                Shot.open("record", "rect")
                return "ok: открыто выделение для записи экрана"
            case "pomodoro":
                if (b === "right" || b === "stop") { Pomodoro.stop(); return "ok: помодоро остановлен" }
                Session.ccTab = 1
                return openPop("control", "pomodoro")
            case "weather":
                if (b === "right" || b === "refresh") { Weather.update(); return "ok: обновление погоды запущено" }
                return openPop("weather", "weather")
            case "media":
                if (b === "middle" || b === "toggle") { Player.toggle(); return "ok: плеер пауза/играть" }
                if (b === "right" || b === "next") { Player.next(); return "ok: следующий трек" }
                if (b === "prev" || b === "previous") { Player.previous(); return "ok: предыдущий трек" }
                if (b === "up" || b === "down") {
                    Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/cider-vol", b])
                    return "ok: громкость плеера " + b
                }
                return openPop("player", "media")
            case "stats":
            case "system": return openPop("system", "stats")
            case "net":
            case "network":
                if (b === "right" || b === "refresh") { Net.refresh(); return "ok: статус сети обновлён" }
                return openPop("network", "net")
            case "ai":
            case "assistant":
                if (b === "right" || b === "clear") { Ai.clear(); return "ok: чат помощника очищен" }
                return openPop("assistant", "ai")
            case "bell":
            case "notifications":
                if (b === "right" || b === "dnd") {
                    Session.dnd = !Session.dnd
                    return "ok: режим «не беспокоить» = " + (Session.dnd ? "вкл" : "выкл")
                }
                if (b === "middle" || b === "clear") { Notifs.clearAll(); return "ok: уведомления очищены" }
                return openPop("notifications", "bell")
            case "status":
            case "control":
                if (b === "middle" || b === "mute") {
                    const a = Pipewire.defaultAudioSink?.audio
                    if (a) a.muted = !a.muted
                    return "ok: звук " + (a?.muted ? "выключен" : "включён")
                }
                if (b === "right" || b === "mic") {
                    const s = Pipewire.defaultAudioSource?.audio
                    if (s) s.muted = !s.muted
                    return "ok: микрофон " + (s?.muted ? "выключен" : "включён")
                }
                if (b === "up" || b === "down") {
                    const a = Pipewire.defaultAudioSink?.audio
                    if (a) a.volume = Math.max(0, Math.min(1, a.volume + (b === "up" ? 0.05 : -0.05)))
                    return "ok: громкость " + Math.round((a?.volume ?? 0) * 100) + "%"
                }
                return openPop("control", "status")
            case "privacy":
                if (b === "right" || b === "toggle") {
                    Session.privacy = !Session.privacy
                    return "ok: приватный режим = " + (Session.privacy ? "вкл" : "выкл")
                }
                return openPop("privacy", "status")
            case "barconfig": return openPop("barconfig", "")
            }
            return "err: неизвестный элемент бара «" + widget + "»"
        }
        function tray(target: string, button: string, screen: string): string {
            return BarLayout.triggerTray((screen || Theme.primaryMonitor).trim(), target, button || "left")
        }
        function add(scope: string, widget: string, zone: string, join: bool): string {
            return BarLayout.addOrMoveWidget(scope, widget, zone, -1, join)
        }
        function remove(scope: string, widget: string): string {
            return BarLayout.removeWidget(scope, widget)
        }
        function move(scope: string, widget: string, delta: int): string {
            return BarLayout.moveWidget(scope, widget, delta)
        }
        function moveZone(scope: string, widget: string, toZone: string, join: bool): string {
            return BarLayout.addOrMoveWidget(scope, widget, toZone, -1, join)
        }
        function join(scope: string, widget: string, mode: string): string {
            return BarLayout.setWidgetJoin(scope, widget, mode)
        }
        function setZone(scope: string, zone: string, spec: string): string {
            return BarLayout.setZoneItems(scope, zone, spec)
        }
        function reset(scope: string): string {
            BarLayout.reset(scope || "primary")
            return "ok: раскладка панели сброшена (" + (scope || "primary") + ")"
        }
    }

    IpcHandler {
        target: "idle"
        function dimNow(): void { idleGuard.previewDim() }
        function screensOff(): void { idleGuard.screensOff() }
        function screensOn(): void { idleGuard.screensOn() }
        function toggle(): void { Session.idleOn = !Session.idleOn }
        function state(): string {
            return JSON.stringify({
                enabled: Session.idleOn, inhibit: Session.idleInhibit,
                dimSec: Session.idleDim, dpmsSec: Session.idleDpms, lockSec: Session.idleLock, suspendSec: Session.idleSuspend,
                lockBeforeSleep: Session.idleLockSleep, respectInhibitors: Session.idleRespect, skipFullscreen: Session.idleSkipFs,
                dimLevel: Session.idleDimLevel
            })
        }
    }
    IpcHandler {
        target: "ai"
        function toggle(): void { Modal.toggle("assistant") }
        function ask(text: string): void { Modal.open("assistant"); Ai.send(text) }
        function clear(): void { Ai.clear() }
        function provider(id: string): void { Ai.setProvider(id, false) } // claude | agy | codex (смена прямо в текущем треде с Context Handoff)
        function agent(on: bool): void { Ai.setAgent(on) }
        function mode(m: string): void { Ai.setInteractionMode(m) }       // default | plan
        function permissions(m: string): void { Ai.setPermissionMode(m) } // supervised | auto-edit | full-access
        function send(text: string): void { Ai.send(text) }               // без открытия окна (если занят — ставит в очередь)
        function steer(text: string): void { Ai.steer(text) }             // прервать и перенаправить активный ход
        function queue(text: string): void { Ai.enqueueMessage(text) }    // добавить в очередь
        function chat(): void { Ai.newChat(Ai.provider) }
        function openChat(id: string): void { Ai.openChat(id) }
        function launchThread(optsJson: string): string { return Ai.launchThread(optsJson) }
        function forkChat(id: string, upToIndex: int, title: string): string { return Ai.forkChat(id, upToIndex, title) }
        function chats(): string { return JSON.stringify(Ai.chatList) }
        function deleteChat(id: string): void { Ai.deleteChat(id) }
        function load(): void { Ai.loadImports() }                         // обновить список разговоров из консоли
        function importChat(provider: string, id: string): void { const it = Ai.importList.find(x => x.provider === provider && x.id === id); if (it) Ai.importChat(it) }
        function approve(decision: string): void { if (Ai.approvals.count > 0) Ai.resolveApproval(Ai.approvals.get(0).rid, decision, false) }
        function attach(path: string): void { Ai.attachPath(path) }
        // состояние для скриптов и проверок
        function state(): string {
            const i = Ai.log.count - 1
            return JSON.stringify({
                busy: Ai.busy,
                provider: Ai.provider,
                providersUsed: Ai.providersUsed,
                agent: Ai.agent,
                interactionMode: Ai.interactionMode,
                permissionMode: Ai.permissionMode,
                chat: Ai.chatId,
                cwd: Ai.cwd,
                gitBranch: Ai.gitInfo?.branch || "",
                isWorktree: !!Ai.gitInfo?.isWorktree,
                msgs: Ai.log.count,
                queued: Ai.queuedMessages.count,
                queueHeld: Ai.queueHeld,
                stashCount: Ai.stashList.length,
                chipsCount: Ai.contextChips.count,
                session: Ai.sessionId,
                sessions: Ai.chatSessions,
                attachments: Ai.attachments.count,
                approvals: Ai.approvals.count,
                pendingQuestion: !!Ai.pendingQuestion,
                activePlan: Ai.activePlan ? Ai.activePlan.title : "",
                tokenUsage: Ai.tokenUsage,
                pending: Ai.approvals.count ? Ai.approvals.get(0).title + " | " + Ai.approvals.get(0).detail : "",
                last: i >= 0 ? { role: Ai.log.get(i).role, text: Ai.log.get(i).text.slice(0, 300), filesJson: Ai.log.get(i).filesJson } : null,
                limits: Ai.limits,
                model: Ai.model,
                effort: Ai.effort
            })
        }
    }
    IpcHandler {
        target: "privacy"
        function toggle(): void { Session.privacy = !Session.privacy }
        function on(): void { Session.privacy = true }
        function off(): void { Session.privacy = false }
        function state(): string {
            return JSON.stringify({ privacy: Session.privacy, count: Privacy.count, mic: Privacy.mic, screen: Privacy.screen, camera: Privacy.camera })
        }
    }
    IpcHandler {
        target: "minidash"
        function toggle(): void { Session.miniOn = !Session.miniOn }
        function state(): string { return JSON.stringify({ enabled: Session.miniOn, output: "HDMI-A-1" }) }
    }
    IpcHandler {
        target: "desk"
        function toggle(): void { Session.deskOn = !Session.deskOn }
        function edit(): void { Session.deskOn = true; Desk.editing = !Desk.editing }
        function widgetToggle(id: string): void { Desk.toggle(id) }
        function set(id: string, key: string, value: string): void {
            const v = value === "true" ? true : value === "false" ? false : (!isNaN(Number(value)) && value.trim() !== "" ? Number(value) : value)
            Desk.set(id, key, v)
        }
        function place(id: string, x: int, y: int): void { Desk.place(id, x, y) }
        function resetPos(): void { Desk.resetPos() }
        function state(): string {
            return JSON.stringify({
                enabled: Session.deskOn, editing: Desk.editing, activeWidgets: Desk.items,
                positions: Desk.pos, config: Desk.cfgAll,
                catalog: Desk.catalog.map(c => ({ id: c.id, label: c.label, shown: Desk.has(c.id), pos: Desk.position(c.id) }))
            })
        }
    }
    IpcHandler {
        target: "modal"
        function toggle(name: string): void { Modal.toggle(name) }
        function openOn(name: string, screen: string): void { Modal.openOn(name, screen) }
        function close(): void { Modal.close() }
        function state(): string {
            return JSON.stringify({ active: Modal.active, closing: Modal.closing, anchorX: Modal.anchorX, screen: Modal.anchorScreen?.name ?? "" })
        }
        // Super+Q: если открыто окно оболочки — закрыть его (чужие окна не трогать), иначе закрыть окно в фокусе
        function dismissOrKill(): void {
            if (Modal.active !== "") Modal.close()
            else Quickshell.execDetached(["mmsg", "dispatch", "killclient"])
        }
    }

    IpcHandler {
        target: "corners"
        function toggle(): void { Session.corners = !Session.corners }
        function radius(r: int): void { Session.cornerRadius = r }
        function state(): string { return Session.corners ? "on " + Session.cornerRadius : "off" }
    }

    IpcHandler {
        target: "tuya"
        function refresh(): void { Tuya.refresh() }
        function allOff(): void { Tuya.allOff() }
        function state(): string { return JSON.stringify({ on: Tuya.onCount, total: Tuya.total, error: Tuya.error, devices: Tuya.devices }) }
    }

    IpcHandler {
        target: "audio"
        function swapOutput(): void { AudioTools.swap() }               // наушники ⇄ колонки
        function step(d: real): void {
            const a = Pipewire.defaultAudioSink?.audio
            if (a) a.volume = Math.max(0, Math.min(1, a.volume + d))
        }
        function volumeUp(): void { step(0.05) }
        function volumeDown(): void { step(-0.05) }
        function setVolume(pct: int): void {
            const a = Pipewire.defaultAudioSink?.audio
            if (a) a.volume = Math.max(0, Math.min(1.5, pct / 100))
        }
        function setMicVolume(pct: int): void {
            const a = Pipewire.defaultAudioSource?.audio
            if (a) a.volume = Math.max(0, Math.min(1.5, pct / 100))
        }
        function toggleMute(): void {
            const a = Pipewire.defaultAudioSink?.audio
            if (a) a.muted = !a.muted
        }
        function toggleMicMute(): void {
            const a = Pipewire.defaultAudioSource?.audio
            if (a) a.muted = !a.muted
        }
        function state(): string {
            const sink = Pipewire.defaultAudioSink
            const source = Pipewire.defaultAudioSource
            const nodes = Pipewire.nodes.values
            const sinks = nodes.filter(n => n.audio && n.isSink && !n.isStream).map(n => ({ id: n.id, name: n.description || n.nickname || n.name, volume: Math.round((n.audio?.volume ?? 0) * 100), muted: !!n.audio?.muted, active: n === sink }))
            const sources = nodes.filter(n => n.audio && !n.isSink && !n.isStream).map(n => ({ id: n.id, name: n.description || n.nickname || n.name, volume: Math.round((n.audio?.volume ?? 0) * 100), muted: !!n.audio?.muted, active: n === source }))
            const streams = nodes.filter(n => n.audio && n.isStream && !n.isSink).map(n => ({ id: n.id, app: n.properties?.["application.name"] || n.description || n.name, volume: Math.round((n.audio?.volume ?? 0) * 100), muted: !!n.audio?.muted }))
            return JSON.stringify({
                sink: sink ? { id: sink.id, name: sink.description || sink.name, volume: Math.round((sink.audio?.volume ?? 0) * 100), muted: !!sink.audio?.muted } : null,
                source: source ? { id: source.id, name: source.description || source.name, volume: Math.round((source.audio?.volume ?? 0) * 100), muted: !!source.audio?.muted } : null,
                sinks: sinks, sources: sources, streams: streams
            })
        }
    }

    IpcHandler {
        target: "player"
        function state(): string {
            return JSON.stringify({
                available: Player.available, playing: Player.playing, player: Player.player, playerName: Player.playerName,
                title: Player.title, artist: Player.artist, album: Player.album, art: Player.art, label: Player.label,
                liked: Player.liked, position: Math.round(Player.livePosition), duration: Math.round(Player.duration),
                volume: Math.round(Player.volume * 100)
            })
        }
        function toggle(): void { Player.toggle() }
        function next(): void { Player.next() }
        function previous(): void { Player.previous() }
        function like(): void { Player.toggleLike() }
        function seek(sec: real): void { Player.seek(sec) }
        function setVolume(pct: int): void { Player.setVolume(Math.max(0, Math.min(100, pct)) / 100) }
    }

    IpcHandler {
        target: "weather"
        function state(): string {
            return JSON.stringify({
                loaded: Weather.loaded, failed: Weather.failed, city: Weather.city,
                temp: Weather.temp, feelsLike: Weather.feelsLike, todayMax: Weather.todayMax, todayMin: Weather.todayMin,
                description: Weather.description, wind: Weather.wind, humidity: Weather.humidity, pressure: Weather.pressure,
                sources: Weather.sources, hourly: Weather.hourly, calendar: Weather.calendar.filter(Boolean)
            })
        }
        function refresh(): void { Weather.update() }
    }

    IpcHandler {
        target: "organizer"
        function state(): string {
            return JSON.stringify({
                pomodoro: { running: Pomodoro.running, label: Pomodoro.label, remainingSec: Pomodoro.remaining, task: Pomodoro.task, minutes: Pomodoro.minutes },
                todos: { current: Todo.current, pending: Todo.pending, finished: Todo.finished, total: Todo.items.length }
            })
        }
        function todoAdd(text: string): void { Todo.add(text) }
        function todoToggle(id: real): void { Todo.toggle(id) }
        function todoRemove(id: real): void { Todo.remove(id) }
        function todoFocus(id: real): void { Todo.focus(id) }
        function todoClearDone(): void { Todo.clearDone() }
        function pomodoroStart(task: string): void { Pomodoro.start(task) }
        function pomodoroStop(): void { Pomodoro.stop() }
    }

    IpcHandler {
        target: "display"
        function state(): string {
            return JSON.stringify({
                averageBrightness: Math.round(Display.average * 100),
                busy: Display.busy,
                monitors: Display.monitors.map(m => ({ bus: m.bus, model: m.model, output: m.output, brightness: Display.values[m.bus] ?? null })),
                nightLight: Session.nightLight,
                nightTemp: Session.nightTemp,
                idleInhibit: Session.idleInhibit
            })
        }
        function setBrightness(outputOrAll: string, pct: int): void {
            const v = Math.max(0, Math.min(100, pct)) / 100
            const t = (outputOrAll || "all").trim()
            if (t === "all" || t === "") Display.setAll(v)
            else {
                const m = Display.monitors.find(x => x.output === t || x.model === t || String(x.bus) === t)
                if (m) Display.set(m.bus, v)
            }
            Display.commit()
        }
        function nightLight(mode: string, temp: int): void {
            const m = (mode || "toggle").trim().toLowerCase()
            if (temp >= 2500 && temp <= 6500) Display.setNightTemp(temp)
            Display.setNightLight(m === "on" || m === "true" || m === "1" ? true : m === "off" || m === "false" || m === "0" ? false : !Session.nightLight)
        }
        function caffeine(mode: string): void {
            const m = (mode || "toggle").trim().toLowerCase()
            Session.idleInhibit = m === "on" || m === "true" || m === "1" ? true : m === "off" || m === "false" || m === "0" ? false : !Session.idleInhibit
        }
    }

    // громкость плеера изменилась (вызывает cider-vol) — показать OSD
    IpcHandler {
        target: "osd"
        function player(): void { Player.refreshVolume(true) }
    }

    // охлаждение (CoolerControl): показания и смена профиля вентиляторов по имени
    IpcHandler {
        target: "cooling"
        function status(): string {
            return JSON.stringify({ available: Cooling.available, cpu: [Cooling.cpuName, Cooling.cpuTemp, Cooling.cpuLoad, Cooling.cpuPower],
                gpu: [Cooling.gpuName, Cooling.gpuTemp, Cooling.gpuHotspot, Cooling.gpuLoad, Cooling.gpuPower],
                profile: Cooling.profiles.find(p => p.uid === Cooling.currentProfile)?.name ?? "",
                profiles: Cooling.profiles.map(p => p.name), managed: Cooling.managed.length,
                fans: Cooling.fans.map(f => f.label + " " + f.rpm), history: Cooling.history.length })
        }
        function profile(name: string): void {
            const p = Cooling.profiles.find(p => p.name === name)
            if (p) Cooling.setProfile(p.uid)
        }
    }

    // Alt+Tab
    IpcHandler {
        target: "switcher"
        function next(): void { Switcher.next() }
        function prev(): void { Switcher.prev() }
        function commit(): void { Switcher.commit() }
        function cancel(): void { Switcher.cancel() }
        function state(): string { return JSON.stringify({ open: Switcher.open, index: Switcher.index, items: Switcher.items.map(c => c.id), mru: Switcher.mru.slice(0, 6) }) }
    }

    // скриншотилка (порт из iNiR)
    IpcHandler {
        target: "region"
        function screenshot(): void { Shot.open("copy", Session.snipMode) }
        function menu(): void { Shot.menu() }
        function edit(): void { Shot.open("edit", Session.snipMode) }
        function ocr(): void { Shot.open("ocr", "rect") }
        function record(): void { Shot.open("record", "rect") }
        function recordSound(): void { Shot.open("record", "rect"); Shot.sound = true }
        function dismiss(): void { Shot.dismiss() }
        function open(action: string, mode: string): void { Shot.open(action, mode) }
        function recording(on: bool): void { Shot.setRecording(on) }
        function state(): string {
            return JSON.stringify({ active: Shot.active, action: Shot.action, mode: Shot.mode, recording: Shot.recording, recordStart: Shot.recordStart })
        }
    }

    // отсчёт перед выключением / перезагрузкой
    IpcHandler {
        target: "power"
        function cancel(): void { Countdown.cancel() }
        function now(): void { Countdown.now() }
        // посмотреть экран отсчёта: ничего не выполняет
        function preview(): void {
            Countdown.start({ key: "R", icon: "\uf021", label: "Перезагрузка", verb: "Перезагрузка через", cmd: ["true"], tint: Theme.primary })
        }
    }

    // режим демонстрации (qs-demo и MCP demo)
    IpcHandler {
        target: "demo"
        function caption(n: string, t: string, s: string): void { Demo.caption(n, t, s) }
        function captionOn(n: string, t: string, s: string, screen: string): void { Demo.caption(n, t, s, screen) }
        function screen(name: string): void { Demo.screenName = (name || "").trim() }
        function clear(): void { Demo.clear() }
        function tab(i: int): void { Session.ccTab = i }
        function expand(what: string): void { Demo.ccExpand = (what || "").trim() }
        function settingsTab(t: string, deskId: string): void {
            Demo.settingsTab = (t || "general").trim()
            if (deskId !== undefined) Demo.deskOpenId = deskId.trim()
        }
        function barScope(sc: string): void { Demo.barScope = (sc || "primary").trim() }
        function clipKind(k: string): void { Demo.clipKind = (k || "all").trim() }
        function emojiGroup(g: int): void { Demo.emojiGroup = Math.max(0, g) }
        function type(text: string): void { Demo.typeQuery(text) }
        function query(text: string): void { Demo.setQuery(text) }
        function osd(kind: string): void {
            const k = (kind || "volume").trim().toLowerCase()
            if (k === "layout" || k === "kbd") Mango.showOsd()
            else Osd.show(k)
        }
        function cursor(x: int, y: int): void { Cursor.setPos(x, y) }
        function state(): string {
            return JSON.stringify({
                active: Demo.active,
                shown: Demo.shown,
                screen: Demo.screenName || Theme.primaryMonitor,
                step: Demo.step,
                title: Demo.title,
                sub: Demo.sub,
                query: Demo.query,
                ccTab: Session.ccTab,
                ccExpand: Demo.ccExpand,
                settingsTab: Demo.settingsTab,
                deskOpenId: Demo.deskOpenId,
                barScope: Demo.barScope,
                clipKind: Demo.clipKind,
                emojiGroup: Demo.emojiGroup,
                modal: Modal.active,
                modalScreen: Modal.anchorScreen?.name ?? null
            })
        }
    }

    IpcHandler {
        target: "notifications"
        function toggleDnd(): void { Session.dnd = !Session.dnd }
        function clear(): void { Notifs.clearAll() }
        // убрать только уведомления приложения (демо подчищает за собой)
        function dismissApp(app: string): void { for (const n of Notifs.history.filter(n => n.appName === app)) n.dismiss() }
        function dismissId(id: int): void { const n = Notifs.history.find(x => x.id === id); if (n) n.dismiss() }
        function state(): string {
            return JSON.stringify({
                dnd: Session.dnd, gaming: Notifs.gaming, count: Notifs.count, popups: Notifs.popups.length,
                items: Notifs.history.slice(0, 30).map(n => ({ id: n.id, app: n.appName, summary: n.summary, body: n.body, time: Notifs.timeOf(n), urgency: n.urgency }))
            })
        }
    }

    Bar {}
    SwitcherWindow {}

    // всплывашки и OSD — только пока есть что показать
    LazyLoader { active: Notifs.popups.length > 0; source: "Toasts.qml" }
    LazyLoader { active: Osd.visible; source: "OsdWindow.qml" }
    LazyLoader { active: Mango.osd; source: "LayoutOsd.qml" }

    LazyLoader { active: Modal.active === "launcher"; source: "modals/AppLauncher.qml" }
    LazyLoader { active: Modal.active === "wallpapers"; source: "modals/WallpaperPicker.qml" }
    LazyLoader { active: Modal.active === "power"; source: "modals/PowerMenu.qml" }
    LazyLoader { active: Modal.active === "cheatsheet"; source: "modals/KeybindSheet.qml" }
    LazyLoader { active: Modal.active === "control"; source: "modals/ControlCenter.qml" }
    LazyLoader { active: Modal.active === "notifications"; source: "modals/NotificationCenter.qml" }
    LazyLoader { active: Modal.active === "weather"; source: "modals/WeatherPopup.qml" }
    LazyLoader { active: Modal.active === "clipboard"; source: "modals/ClipboardPicker.qml" }
    LazyLoader { active: Modal.active === "system"; source: "modals/SystemPopup.qml" }
    LazyLoader { active: Modal.active === "player"; source: "modals/PlayerPopup.qml" }
    LazyLoader { active: Modal.active === "overview"; source: "modals/Overview.qml" }
    LazyLoader { active: Modal.active === "emoji"; source: "modals/EmojiPicker.qml" }
    LazyLoader { active: Modal.active === "calendar"; source: "modals/CalendarPopup.qml" }
    LazyLoader { active: Modal.active === "barconfig"; source: "modals/BarConfig.qml" }
    LazyLoader { active: Modal.active === "network"; source: "modals/NetworkPopup.qml" }
    LazyLoader { active: Modal.active === "settings"; source: "modals/ShellSettings.qml" }
    LazyLoader { active: Modal.active === "assistant"; source: "modals/Assistant.qml" }
    IpcHandler {
        target: "blur"
        function toggle(): void { Session.blurOff = !Session.blurOff }
        function off(): void { Session.blurOff = true }
        function on(): void { Session.blurOff = false }
        function state(): string { return Session.blurOff ? "off" : "on" }
    }
    IpcHandler {
        target: "wallgroups"
        function state(): string { return JSON.stringify(WallGroups.groups.map(g => ({ id: g.id, name: g.name, outputs: WallGroups.monitorsOf(g.id), sources: g.sources.length, order: g.order, interval: g.interval, enabled: g.enabled, left: WallGroups.secondsLeft(g), last: g.last }))) }
        function next(id: string): void { WallGroups.rotate(id) }
        function create(name: string): string { return WallGroups.create(name, [], []) }
        function remove(id: string): void { WallGroups.remove(id) }
        function addSource(id: string, path: string): void { WallGroups.addSource(id, path) }
        function monitor(name: string, id: string): void { WallGroups.setMonitor(name, id) }          // id пустой — монитор без группы
        function order(id: string, o: string): void { WallGroups.patch(id, { order: o }) }
    }
    LazyLoader { active: Modal.active === "audio"; source: "modals/AudioPicker.qml" }
    ScreenCorners {}
    LazyLoader { active: Modal.active === "tuya"; source: "modals/TuyaPanel.qml" }
    LazyLoader { active: Modal.active === "wallgroups"; source: "modals/WallGroups.qml" }
    LazyLoader { active: Modal.active === "wininfo"; source: "modals/WindowInfo.qml" }
    LazyLoader { active: Modal.active === "privacy"; source: "modals/PrivacyPopup.qml" }

    LazyLoader { active: Countdown.active; source: "CountdownWindow.qml" }
    LazyLoader { active: Demo.shown; source: "DemoCaption.qml" }
    LazyLoader { active: Shot.active; source: "shot/Selector.qml" }
    LazyLoader { active: Shot.editorPath !== ""; source: "shot/Editor.qml" }
}
