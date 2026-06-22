import Foundation
import Combine

// 定型文リストの保存・読み込みを担当
// JSONファイルとして ~/Library/Application Support/Petaco/snippets.json に保存する
final class SnippetStore: ObservableObject {
    @Published var snippets: [Snippet] = []

    private let fileURL: URL

    init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Petaco", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        self.fileURL = dir.appendingPathComponent("snippets.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            // 初回起動時はサンプルを1つ入れておく
            snippets = [
                Snippet(content: "ここに定型文が入ります",
                        keyCode: KeyCodeMap.defaultFunctionKeyCodes[0],
                        modifiers: Snippet.defaultModifiers)
            ]
            save()
            return
        }
        if let decoded = try? JSONDecoder().decode([Snippet].self, from: data) {
            let migrated = migrateNumberKeysToFunctionKeys(decoded)
            snippets = migrated
            if migrated != decoded {
                save()
            }
        }
    }

    // v1では数字キー(1-0)をデフォルト割り当てにしていたが、アプリとの衝突が多いためFキーへ移行した
    private func migrateNumberKeysToFunctionKeys(_ snippets: [Snippet]) -> [Snippet] {
        let oldToNew = Dictionary(uniqueKeysWithValues: zip(
            KeyCodeMap.legacyNumberKeyCodes,
            KeyCodeMap.defaultFunctionKeyCodes
        ))
        return snippets.map { snippet in
            guard snippet.modifiers == Snippet.defaultModifiers,
                  let newKeyCode = oldToNew[snippet.keyCode] else { return snippet }
            var migrated = snippet
            migrated.keyCode = newKeyCode
            return migrated
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(snippets) {
            try? data.write(to: fileURL)
        }
    }

    // 新規追加。デフォルトキーは使われていないファンクションキーを自動割り当て
    func addSnippet(content: String) {
        let usedCodes = Set(snippets.map { $0.keyCode })
        let nextCode = KeyCodeMap.defaultFunctionKeyCodes.first { !usedCodes.contains($0) }
            ?? KeyCodeMap.defaultFunctionKeyCodes[0]
        let snippet = Snippet(content: content,
                               keyCode: nextCode, modifiers: Snippet.defaultModifiers)
        snippets.append(snippet)
        save()
    }

    func update(_ snippet: Snippet) {
        if let idx = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[idx] = snippet
            save()
        }
    }

    func delete(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
        save()
    }

    // 指定のキー・修飾キーと一致する定型文を探す（重複チェックにも使う）
    func snippet(forKeyCode keyCode: UInt32, modifiers: UInt32) -> Snippet? {
        snippets.first { $0.keyCode == keyCode && $0.modifiers == modifiers }
    }
}
