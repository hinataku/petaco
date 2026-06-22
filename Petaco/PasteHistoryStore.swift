import Foundation
import Combine
import AppKit

// コピー履歴の保存・読み込みを担当
// JSONファイルとして ~/Library/Application Support/Petaco/history.json に保存する
final class PasteHistoryStore: ObservableObject {
    @Published var items: [PasteHistoryItem] = []

    // 履歴として保持する最大件数（増えすぎ防止）
    private let maxItems = 50

    private let fileURL: URL

    init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Petaco", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        self.fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([PasteHistoryItem].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL)
        }
    }

    // コピー検出時に呼ぶ。同じ内容が既にあれば古い方を消し、最新として先頭に追加する
    func record(content: String) {
        items.removeAll { $0.content == content }
        let newItem = PasteHistoryItem(content: content)
        items.insert(newItem, at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        save()
    }

    func delete(_ item: PasteHistoryItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clearAll() {
        items.removeAll()
        save()
    }
}

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
    }

    // ペタコ自身が貼り付けのため一時的に書き換えたクリップボードは、コピー履歴に含めない。
    static func ignore(changeCount: Int) {
        ignoredChangeCounts.insert(changeCount)
    }

    deinit {
        timer?.invalidate()
    }
}
