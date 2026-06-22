import Foundation
import Combine
import AppKit
import SwiftUI
import Carbon.HIToolbox
import CoreGraphics

// 設定したショートカット（複数可）で一覧オーバーレイを開閉する。
final class QuickPickManager: ObservableObject {
    // オーバーレイに表示するコピー履歴の選択肢
    struct Entry: Identifiable, Equatable {
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
    private let usesOutsideClickMonitor: Bool
    private var pasteTargetApplication: NSRunningApplication?
    private var historySubscription: AnyCancellable?
    private var shortcutSubscription: AnyCancellable?
    private var shortcutEditingSubscription: AnyCancellable?
    private let triggerHotKeySignature = OSType(0x51505452) // "QPTR"
    private var triggerHotKeyRefs: [EventHotKeyRef] = []
    private var triggerEventHandler: EventHandlerRef?
    private var overlayPanel: NSPanel?

    init(
        store: SnippetStore,
        historyStore: PasteHistoryStore,
        shortcutStore: QuickPickShortcutStore,
        startsMonitoring: Bool = true,
        startsSessionMonitoring: Bool = true,
        usesOutsideClickMonitor: Bool = true
    ) {
        self.store = store
        self.historyStore = historyStore
        self.shortcutStore = shortcutStore
        self.startsSessionMonitoring = startsSessionMonitoring
        self.usesOutsideClickMonitor = usesOutsideClickMonitor
        self.historySubscription = historyStore.$items.sink { [weak self] _ in
            guard let self, self.isShowingOverlay else { return }
            self.refreshEntries(resetSelection: true)
        }
        self.shortcutSubscription = shortcutStore.$shortcuts
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, !self.isShowingOverlay, !self.shortcutStore.isEditing else { return }
                    self.registerTriggerHotKeys()
                }
            }
        self.shortcutEditingSubscription = shortcutStore.$isEditing
            .dropFirst()
            .sink { [weak self] isEditing in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if isEditing {
                        self.unregisterTriggerHotKeys()
                    } else if !self.isShowingOverlay {
                        self.registerTriggerHotKeys()
                    }
                }
            }
        if startsMonitoring {
            startMonitoring()
        }
    }

    // 設定したショートカットだけをCarbonへ登録する。NSEventの全キー監視は使わない。
    private func startMonitoring() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, eventRef, userData) -> OSStatus in
            guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<QuickPickManager>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard hotKeyID.signature == manager.triggerHotKeySignature else { return OSStatus(eventNotHandledErr) }
            manager.handlePossibleTrigger()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &triggerEventHandler)

        registerTriggerHotKeys()
    }

    private func registerTriggerHotKeys() {
        guard !shortcutStore.isEditing else { return }
        unregisterTriggerHotKeys()
        for (index, shortcut) in shortcutStore.shortcuts.enumerated() {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: triggerHotKeySignature, id: UInt32(index + 1))
            let modifiers = Modifiers(rawValue: shortcut.modifiers).carbonHotKeyModifiers
            let status = RegisterEventHotKey(shortcut.keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                triggerHotKeyRefs.append(ref)
                PetacoLog.hotkey.notice("Registered quick pick trigger keyCode=\(shortcut.keyCode, privacy: .public), modifiers=\(modifiers, privacy: .public)")
            } else {
                PetacoLog.hotkey.error("Failed to register quick pick trigger status=\(status, privacy: .public)")
            }
        }
    }

    private func unregisterTriggerHotKeys() {
        for ref in triggerHotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        triggerHotKeyRefs.removeAll()
    }

    private func handlePossibleTrigger() {
        PetacoLog.hotkey.notice("Received quick pick trigger, overlayVisible=\(self.isShowingOverlay, privacy: .public)")
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
        refreshEntries()
        selectedIndex = 0
        isShowingOverlay = !entries.isEmpty
        PetacoLog.hotkey.notice("Prepared quick pick entries=\(self.entries.count, privacy: .public), showing=\(self.isShowingOverlay, privacy: .public)")
        if isShowingOverlay {
            presentPanel()
        }
    }

    private func refreshEntries(resetSelection: Bool = false) {
        let historyEntries = historyStore.items.map { Entry(id: $0.id, content: $0.content) }
        entries = historyEntries
        if entries.isEmpty || resetSelection {
            selectedIndex = 0
        } else {
            selectedIndex = min(selectedIndex, entries.count - 1)
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
    private var arrowRepeatTimer: Timer?
    private var mouseMonitor: Any?

    private func startSessionMonitoring() {
        stopSessionMonitoring()

        installSessionHotKeyHandlerIfNeeded()
        registerSessionHotKey(.up, keyCode: UInt32(kVK_UpArrow))
        registerSessionHotKey(.down, keyCode: UInt32(kVK_DownArrow))
        registerSessionHotKey(.confirm, keyCode: UInt32(kVK_Return))
        registerSessionHotKey(.cancel, keyCode: UInt32(kVK_Escape))

        sessionCancelMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.isShowingOverlay, !event.isARepeat else { return }
            let handledKeyCodes: Set<UInt16> = [
                UInt16(kVK_UpArrow), UInt16(kVK_DownArrow), UInt16(kVK_Return), UInt16(kVK_Escape)
            ]
            guard !handledKeyCodes.contains(event.keyCode) else { return }
            DispatchQueue.main.async { self.cancelOverlay() }
        }
        if usesOutsideClickMonitor {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self, let panel = self.overlayPanel else { return }
                let screenPoint = NSEvent.mouseLocation
                if !NSMouseInRect(screenPoint, panel.frame, false) {
                    DispatchQueue.main.async { self.cancelOverlay() }
                }
            }
        }
    }

    private func stopSessionMonitoring() {
        PetacoLog.hotkey.notice("Stopping quick pick session hotkeys count=\(self.sessionHotKeyRefs.count, privacy: .public)")
        for ref in sessionHotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        sessionHotKeyRefs.removeAll()
        if let sessionCancelMonitor {
            NSEvent.removeMonitor(sessionCancelMonitor)
        }
        sessionCancelMonitor = nil
        stopArrowRepeat()
        if let mouseMonitor = mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        mouseMonitor = nil
    }

    private func installSessionHotKeyHandlerIfNeeded() {
        guard sessionHotKeyHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, eventRef, userData) -> OSStatus in
            guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<QuickPickManager>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard hotKeyID.signature == manager.sessionHotKeySignature,
                  let id = SessionHotKeyID(rawValue: hotKeyID.id) else { return OSStatus(eventNotHandledErr) }
            manager.handleSessionHotKey(id)
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &sessionHotKeyHandler)
    }

    private func registerSessionHotKey(_ id: SessionHotKeyID, keyCode: UInt32, modifiers: UInt32 = 0) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: sessionHotKeySignature, id: id.rawValue)
        if RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr,
           let ref {
            sessionHotKeyRefs.append(ref)
        }
    }

    private func handleSessionHotKey(_ id: SessionHotKeyID) {
        guard isShowingOverlay else { return }

        switch id {
        case .up:
            moveSelection(by: -1)
            startArrowRepeat(keyCode: UInt16(kVK_UpArrow), delta: -1)
        case .down:
            moveSelection(by: 1)
            startArrowRepeat(keyCode: UInt16(kVK_DownArrow), delta: 1)
        case .confirm:
            confirmAndPaste()
        case .cancel:
            cancelOverlay()
        }
    }

    private func startArrowRepeat(keyCode: UInt16, delta: Int) {
        stopArrowRepeat()
        let delay: TimeInterval = 0.4
        let interval: TimeInterval = 0.12
        arrowRepeatTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.arrowRepeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
                guard let self,
                      self.isShowingOverlay,
                      CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode)) else {
                    timer.invalidate()
                    self?.arrowRepeatTimer = nil
                    return
                }
                self.moveSelection(by: delta)
            }
        }
    }

    private func stopArrowRepeat() {
        arrowRepeatTimer?.invalidate()
        arrowRepeatTimer = nil
    }

    private func moveSelection(by delta: Int) {
        guard !entries.isEmpty else { return }
        let count = entries.count
        selectedIndex = ((selectedIndex + delta) % count + count) % count
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
        closeOverlay()
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
