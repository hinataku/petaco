import AppKit
import UserNotifications

// NSPasteboardにはコピー通知がないため、変更カウントを定期的に監視する。
// アプリ起動後にユーザーがコピーした文字列だけを履歴へ追加する。
final class ClipboardMonitor {
    private static var ignoredChangeCounts = Set<Int>()
    private let historyStore: PasteHistoryStore
    private var changeCount: Int
    private var timer: Timer?

    init(historyStore: PasteHistoryStore) {
        self.historyStore = historyStore
        self.changeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.captureIfNeeded()
        }
    }

    private func captureIfNeeded() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount
        if Self.ignoredChangeCounts.remove(changeCount) != nil { return }
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        historyStore.record(content: text)
        showCopyNotification(text: text)
    }

    private var lastNotifiedText: String?

    private func showCopyNotification(text: String) {
        guard text != lastNotifiedText else { return }
        lastNotifiedText = text

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["petaco.copy"])

        let content = UNMutableNotificationContent()
        content.title = "コピーしました"
        content.body = text.count > 50 ? String(text.prefix(50)) + "…" : text

        let request = UNNotificationRequest(identifier: "petaco.copy", content: content, trigger: nil)
        center.add(request)
    }

    // ペタコ自身が貼り付けのため一時的に書き換えたクリップボードは、コピー履歴に含めない。
    static func ignore(changeCount: Int) {
        ignoredChangeCounts.insert(changeCount)
    }

    deinit {
        timer?.invalidate()
    }
}
