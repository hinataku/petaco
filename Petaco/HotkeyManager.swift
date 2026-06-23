import Foundation
import CoreGraphics
import AppKit

// 全定型文に対応するグローバルホットキーを CGEventTap で監視し、押されたらペーストを実行する。
// Carbon の RegisterEventHotKey と異なり、XP-Pen 等のデバイスドライバ経由のキーも検出できる。
final class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let store: SnippetStore
    private var isSuspended = false

    init(store: SnippetStore, historyStore: PasteHistoryStore) {
        self.store = store
        installEventTap()
    }

    private func installEventTap() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { (_, _, event, userData) -> Unmanaged<CGEvent>? in
                guard let userData else { return Unmanaged.passRetained(event) }
                return Unmanaged<HotkeyManager>.fromOpaque(userData)
                    .takeUnretainedValue()
                    .handleEvent(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            PetacoLog.hotkey.error("CGEventTap の作成に失敗しました。アクセシビリティ権限を確認してください。")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        PetacoLog.hotkey.notice("CGEventTap を登録しました")
    }

    private func handleEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard !isSuspended else { return Unmanaged.passRetained(event) }

        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        for snippet in store.snippets {
            guard snippet.keyCode == keyCode,
                  Modifiers(rawValue: snippet.modifiers).matches(flags) else { continue }

            PetacoLog.hotkey.notice("ホットキー一致 keyCode=\(keyCode, privacy: .public)")
            DispatchQueue.main.async {
                PasteManager.paste(text: snippet.content, restorePreviousApplication: false)
            }
            return nil // イベントを消費して背後のアプリへ渡さない
        }

        return Unmanaged.passRetained(event)
    }

    // 現在の snippets に合わせてホットキーを更新する（CGEventTap は常時起動しているため再登録不要）
    func reloadAllHotkeys() {
        isSuspended = false
    }

    // キー入力キャプチャ中はホットキーを無効化する
    func suspendAllHotkeys() {
        isSuspended = true
    }

    deinit {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
    }
}
