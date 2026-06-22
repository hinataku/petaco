import Foundation
import Carbon.HIToolbox
import AppKit

// 全定型文に対応するグローバルホットキーを登録し、押されたらペーストを実行する
final class HotkeyManager {
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var hotKeyIDToSnippetID: [UInt32: UUID] = [:]
    private var nextHotKeyID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private let store: SnippetStore
    private let historyStore: PasteHistoryStore

    init(store: SnippetStore, historyStore: PasteHistoryStore) {
        self.store = store
        self.historyStore = historyStore
        installEventHandler()
    }

    // Carbonのイベントハンドラを1つ設置し、押されたホットキーIDから該当する定型文を特定する
    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                       eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), { (_, eventRef, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

            var hotKeyID = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                               nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)

            manager.handleHotKeyPressed(id: hotKeyID.id)
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    private func handleHotKeyPressed(id: UInt32) {
        guard let snippetID = hotKeyIDToSnippetID[id],
              let snippet = store.snippets.first(where: { $0.id == snippetID }) else {
            PetacoLog.hotkey.error("Received an unregistered hotkey id=\(id, privacy: .public)")
            return
        }
        PetacoLog.hotkey.notice("Received hotkey id=\(id, privacy: .public), textLength=\(snippet.content.count, privacy: .public)")
        // コピー履歴はClipboardMonitorが管理するため、貼り付け時には追加しない。
        PasteManager.paste(text: snippet.content, restorePreviousApplication: false)
    }

    // 現在の store.snippets の内容に合わせて、全ホットキーを登録し直す
    func reloadAllHotkeys() {
        unregisterAllHotkeys()

        for snippet in store.snippets {
            register(snippet: snippet)
        }
    }

    // キー変更の入力待ち中など、既存ショートカットを一時的に停止する。
    func suspendAllHotkeys() {
        unregisterAllHotkeys()
    }

    private func unregisterAllHotkeys() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        hotKeyIDToSnippetID.removeAll()
    }

    private func register(snippet: Snippet) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x53504254), id: nextHotKeyID) // "SPBT"
        var ref: EventHotKeyRef?

        let modifiers = Modifiers(rawValue: snippet.modifiers).carbonHotKeyModifiers
        let status = RegisterEventHotKey(snippet.keyCode, modifiers,
                                          hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref = ref {
            hotKeyRefs[nextHotKeyID] = ref
            hotKeyIDToSnippetID[nextHotKeyID] = snippet.id
            PetacoLog.hotkey.notice("Registered hotkey id=\(self.nextHotKeyID, privacy: .public), keyCode=\(snippet.keyCode, privacy: .public), modifiers=\(modifiers, privacy: .public)")
            nextHotKeyID += 1
        } else {
            PetacoLog.hotkey.error("Failed to register keyCode=\(snippet.keyCode, privacy: .public), modifiers=\(modifiers, privacy: .public), status=\(status, privacy: .public)")
        }
    }aN5!9iLnPrdy
}
