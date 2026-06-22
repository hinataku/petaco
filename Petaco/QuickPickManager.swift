import Foundation
import Combine
import AppKit
import SwiftUI
import Carbon.HIToolbox

// 設定したショートカット（初期値: ⌘⇧Space）で一覧オーバーレイを開閉する。
final class QuickPickManager: ObservableObject {
    // オーバーレイに表示する選択肢（定型文 + 履歴をまとめたもの）
    struct Entry: Identifiable {
        let id: UUID
        let content: String
    }

    @Published var isShowingOverlay = false
    @Published var entries: [Entry] = []
    @Published var selectedIndex: Int = 0
    private let store: SnippetStore
    private let historyStore: PasteHistoryStore
    private let shortcutStore: QuickPickShortcutStore
    private let startsSessionMonitoring: Bool
    private var pasteTargetApplication: NSRunningApplication?
    private var globalKeyDownMonitor: Any?
    private var localMonitor: Any?
    private var overlayPanel: NSPanel?

    init(
        store: SnippetStore,
        historyStore: PasteHistoryStore,
        shortcutStore: QuickPickShortcutStore,
        startsMonitoring: Bool = true,
        startsSessionMonitoring: Bool = true
    ) {
        self.store = store
        self.historyStore = historyStore
        self.shortcutStore = shortcutStore
        self.startsSessionMonitoring = startsSessionMonitoring
        if startsMonitoring {
            startMonitoring()
        }
    }

    // 設定したショートカットの押下をグローバルに監視開始
    private func startMonitoring() {
        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handlePossibleTrigger(event)
        }
        // アプリ自身がフォーカスを持っている場合（自分のウィンドウ操作中）にも検知できるよう、ローカル監視も併用
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handlePossibleTrigger(event)
            return event
        }
    }

    private func handlePossibleTrigger(_ event: NSEvent) {
        // 押し続けた際のキーリピートで、開いた直後に閉じないようにする。
        guard !event.isARepeat else { return }
        guard event.keyCode == UInt16(shortcutStore.keyCode) else { return }
        let relevantFlags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard relevantFlags == modifierFlags(for: shortcutStore.modifiers) else { return }

        // 既に表示中なら閉じる（トグルとして使えるようにする）
        if isShowingOverlay {
            cancelOverlay()
            return
        }

        showOverlay()
        if startsSessionMonitoring {
            startSessionMonitoring()
        }
    }

    private func showOverlay() {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        if frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            pasteTargetApplication = frontmostApplication
        }
        PetacoLog.focus.notice("Quick pick opened; target=\(self.pasteTargetApplication?.localizedName ?? "Unknown", privacy: .public) pid=\(self.pasteTargetApplication?.processIdentifier ?? 0, privacy: .public)")
        let snippetEntries = store.snippets.map { Entry(id: $0.id, content: $0.content) }
        let historyEntries = historyStore.items.map { Entry(id: $0.id, content: $0.content) }
        entries = snippetEntries + historyEntries
        selectedIndex = 0
        isShowingOverlay = !entries.isEmpty
        if isShowingOverlay {
            presentPanel()
        }
    }

    // SwiftUIのオーバーレイをホストする、フォーカスを奪わない小さなパネルウィンドウを表示する
    private func presentPanel() {
        if overlayPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .popUpMenu
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
            panel.contentView = NSHostingView(rootView: QuickPickOverlayView(manager: self))
            overlayPanel = panel
        }

        if let screenFrame = NSScreen.main?.frame {
            let panelSize = overlayPanel?.frame.size ?? NSSize(width: 360, height: 200)
            let origin = NSPoint(
                x: screenFrame.midX - panelSize.width / 2,
                y: screenFrame.midY - panelSize.height / 2
            )
            overlayPanel?.setFrameOrigin(origin)
        }
        overlayPanel?.orderFrontRegardless()
    }

    // オーバーレイ表示中だけ有効なCarbonホットキー。イベントタップを使わず、
    // 矢印キーなどを背後のアプリへ渡さずに消費できる。
    private enum SessionHotKeyID: UInt32 {
        case up = 1, down, confirm, cancel
    }
    private let sessionHotKeySignature = OSType(0x51504B53) // "QPHS"
    private var sessionHotKeyRefs: [EventHotKeyRef] = []
    private var sessionHotKeyHandler: EventHandlerRef?
    private var sessionCancelMonitor: Any?
    private var mouseMonitor: Any?

    private func startSessionMonitoring() {
        // 既に動いていれば一旦解除してから張り直す（多重登録防止）
        stopSessionMonitoring()

        installSessionHotKeyHandlerIfNeeded()
        registerSessionHotKey(.up, keyCode: UInt32(kVK_UpArrow))
        registerSessionHotKey(.down, keyCode: UInt32(kVK_DownArrow))
        registerSessionHotKey(.confirm, keyCode: UInt32(kVK_Return))
        registerSessionHotKey(.cancel, keyCode: UInt32(kVK_Escape))

        // それ以外のキーは一覧を閉じる。イベントを通過させるため、以後の操作は
        // 元アプリがそのまま受け取れる。
        sessionCancelMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.isShowingOverlay, !event.isARepeat else { return }
            let handledKeyCodes: Set<UInt16> = [
                UInt16(kVK_UpArrow), UInt16(kVK_DownArrow), UInt16(kVK_Return), UInt16(kVK_Escape)
            ]
            guard !handledKeyCodes.contains(event.keyCode) else { return }
            DispatchQueue.main.async { self.cancelOverlay() }
        }
        // オーバーレイ外のクリックで閉じる
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let panel = self.overlayPanel else { return }
            let screenPoint = NSEvent.mouseLocation
            if !NSMouseInRect(screenPoint, panel.frame, false) {
                DispatchQueue.main.async { self.cancelOverlay() }
            }
        }
    }

    private func stopSessionMonitoring() {
        for ref in sessionHotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        sessionHotKeyRefs.removeAll()
        if let sessionCancelMonitor {
            NSEvent.removeMonitor(sessionCancelMonitor)
        }
        sessionCancelMonitor = nil
        if let mouseMonitor = mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        mouseMonitor = nil
    }

    private func installSessionHotKeyHandlerIfNeeded() {
        guard sessionHotKeyHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, eventRef, userData) -> OSStatus in
            guard let eventRef, let userData else { return noErr }
            let manager = Unmanaged<QuickPickManager>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard hotKeyID.signature == manager.sessionHotKeySignature,
                  let id = SessionHotKeyID(rawValue: hotKeyID.id) else { return noErr }
            manager.handleSessionHotKey(id)
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &sessionHotKeyHandler)
    }

    private func registerSessionHotKey(_ id: SessionHotKeyID, keyCode: UInt32) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: sessionHotKeySignature, id: id.rawValue)
        if RegisterEventHotKey(keyCode, 0, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr,
           let ref {
            sessionHotKeyRefs.append(ref)
        }
    }

    private func handleSessionHotKey(_ id: SessionHotKeyID) {
        guard isShowingOverlay else { return }

        switch id {
        case .up:
            moveSelection(by: -1)
        case .down:
            moveSelection(by: 1)
        case .confirm:
            confirmAndPaste()
        case .cancel:
            cancelOverlay()
        }
    }

    private func moveSelection(by delta: Int) {
        guard !entries.isEmpty else { return }
        let count = entries.count
        selectedIndex = ((selectedIndex + delta) % count + count) % count
    }

    private func modifierFlags(for modifiers: UInt32) -> NSEvent.ModifierFlags {
        let value = Modifiers(rawValue: modifiers)
        var flags: NSEvent.ModifierFlags = []
        if value.contains(.command) { flags.insert(.command) }
        if value.contains(.shift) { flags.insert(.shift) }
        if value.contains(.option) { flags.insert(.option) }
        if value.contains(.control) { flags.insert(.control) }
        return flags
    }

    func selectAndPaste(at index: Int) {
        selectedIndex = index
        confirmAndPaste()
    }

    private func confirmAndPaste() {
        guard entries.indices.contains(selectedIndex) else {
            closeOverlay()
            return
        }
        let content = entries[selectedIndex].content
        // 先にイベントタップを解除する。貼り付け準備より後にすると、直後の次キーを
        // オーバーレイが吸収してキーリピート開始まで入力が止まることがある。
        closeOverlay()
        // 表示前に操作していたアプリを貼り付け先として固定し、Cmd+V まで実行する。
        PasteManager.paste(text: content, targetApplication: pasteTargetApplication) { pastedText in
            DispatchQueue.main.async {
                self.historyStore.record(content: pastedText)
            }
        }
    }

    private func cancelOverlay() {
        closeOverlay()
    }

    private func closeOverlay() {
        PetacoLog.focus.notice("Quick pick closed")
        isShowingOverlay = false
        entries = []
        stopSessionMonitoring()
        overlayPanel?.orderOut(nil)
    }
}
