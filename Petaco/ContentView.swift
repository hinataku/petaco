import SwiftUI

struct ContentView: View {
    @ObservedObject var store: SnippetStore
    @ObservedObject var historyStore: PasteHistoryStore
    @ObservedObject var quickPickShortcutStore: QuickPickShortcutStore
    @StateObject private var launchAtLogin = LaunchAtLoginManager()
    let hotkeyManager: HotkeyManager

    @State private var editingSnippet: Snippet?
    @State private var isAddingNew = false
    @State private var duplicateWarning: String?

    // 長押しでプレビューを出す対象のID（nilなら非表示）
    @State private var previewingID: UUID?
    @State private var isCapturingQuickPickShortcut = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                snippetListSection
                    .frame(minWidth: 320, idealWidth: 380)

                Divider()

                historySection
                    .frame(minWidth: 260, idealWidth: 300)
            }
            .frame(minWidth: 640, minHeight: 420)

            if let snippet = editingSnippet {
                editorOverlay(snippet: snippet, isNew: false) {
                    editingSnippet = nil
                }
            } else if isAddingNew {
                editorOverlay(snippet: newSnippetTemplate(), isNew: true) {
                    isAddingNew = false
                }
            }
        }
        .onAppear {
            hotkeyManager.reloadAllHotkeys()
            checkDuplicates()
        }
    }

    // MARK: - 左側: 登録済み定型文一覧
    private var snippetListSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ペタコ")
                    .font(.title2)
                    .bold()
                Spacer()
                Button {
                    isAddingNew = true
                } label: {
                    Label("追加", systemImage: "plus")
                }
            }
            .padding()

            Toggle("PC起動時に自動的に立ち上げる", isOn: $launchAtLogin.isEnabled)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .onAppear {
                    launchAtLogin.refresh()
                }

            if let warning = duplicateWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            List {
                ForEach(store.snippets) { snippet in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snippet.content)
                                .font(.body)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(shortcutLabel(for: snippet))
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(6)

                        PasteButton(id: snippet.id, content: snippet.content,
                                    onPaste: pasteFromWindow,
                                    previewingID: $previewingID)

                        Button {
                            editingSnippet = snippet
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        Button {
                            store.delete(snippet)
                            hotkeyManager.reloadAllHotkeys()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - 右側: 貼り付け履歴
    private var historySection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("履歴ショートカット")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(quickPickShortcutLabel)
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(6)
                Button(isCapturingQuickPickShortcut ? "キーを押してください..." : "変更") {
                    isCapturingQuickPickShortcut = true
                }
                .font(.caption)
                if isCapturingQuickPickShortcut {
                    KeyCaptureView(
                        keyCode: $quickPickShortcutStore.keyCode,
                        modifiers: $quickPickShortcutStore.modifiers,
                        isCapturing: $isCapturingQuickPickShortcut
                    )
                    .frame(width: 1, height: 1)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, 4)

            HStack {
                Text("コピー履歴")
                    .font(.title3)
                    .bold()
                Spacer()
                if !historyStore.items.isEmpty {
                    Button("すべて削除") {
                        historyStore.clearAll()
                    }
                    .font(.caption)
                }
            }
            .padding()

            if historyStore.items.isEmpty {
                Spacer()
                Text("まだコピー履歴がありません")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(historyStore.items) { item in
                        HStack {
                            Text(item.content)
                                .font(.body)
                                .lineLimit(2)
                            Spacer()

                            PasteButton(id: item.id, content: item.content,
                                        onPaste: pasteFromWindow,
                                        previewingID: $previewingID)

                            Button {
                                historyStore.delete(item)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    // 一覧・履歴の貼り付けボタンから実行する。コピー履歴への記録はClipboardMonitorが担当する。
    private func pasteFromWindow(_ text: String) {
        PasteManager.paste(text: text)
    }

    private func shortcutLabel(for snippet: Snippet) -> String {
        let mods = Modifiers(rawValue: snippet.modifiers)
        return mods.displaySymbols + KeyCodeMap.char(for: snippet.keyCode)
    }

    private var quickPickShortcutLabel: String {
        let modifiers = Modifiers(rawValue: quickPickShortcutStore.modifiers)
        return modifiers.displaySymbols + KeyCodeMap.char(for: quickPickShortcutStore.keyCode)
    }

    private func newSnippetTemplate() -> Snippet {
        let usedCodes = Set(store.snippets.map { $0.keyCode })
        let nextCode = KeyCodeMap.defaultFunctionKeyCodes.first { !usedCodes.contains($0) }
            ?? KeyCodeMap.defaultFunctionKeyCodes[0]
        return Snippet(content: "", keyCode: nextCode, modifiers: Snippet.defaultModifiers)
    }

    private func editorOverlay(snippet: Snippet, isNew: Bool, onDismiss: @escaping () -> Void) -> some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            SnippetEditView(
                store: store,
                onSaved: {
                    hotkeyManager.reloadAllHotkeys()
                    checkDuplicates()
                },
                onDismiss: onDismiss,
                snippet: snippet,
                isNew: isNew
            )
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 20)
        }
    }

    // 同じキー組み合わせが複数の定型文に割り当てられていないか確認
    private func checkDuplicates() {
        var seen: [String: Int] = [:]
        for s in store.snippets {
            let key = "\(s.modifiers)-\(s.keyCode)"
            seen[key, default: 0] += 1
        }
        if seen.values.contains(where: { $0 > 1 }) {
            duplicateWarning = "⚠️ 同じショートカットキーが複数の定型文に割り当てられています。最後に登録したホットキーのみ有効になります。"
        } else {
            duplicateWarning = nil
        }
    }
}

// 通常クリックで即時貼り付け、長押しでプレビュー表示する貼り付けボタン
private struct PasteButton: View {
    let id: UUID
    let content: String
    let onPaste: (String) -> Void
    @Binding var previewingID: UUID?

    // 長押しが発火したら、続くクリックを無視するためのフラグ
    @State private var didLongPress = false

    var body: some View {
        Button {
            if didLongPress {
                // 長押し直後に発生する余分なクリックは無視する
                didLongPress = false
                return
            }
            onPaste(content)
        } label: {
            Image(systemName: "doc.on.clipboard")
        }
        .buttonStyle(.borderless)
        .help("クリックで貼り付け／長押しでプレビュー")
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                didLongPress = true
                previewingID = id
            }
        )
        .popover(isPresented: Binding(
            get: { previewingID == id },
            set: { isPresented in if !isPresented { previewingID = nil } }
        )) {
            PastePreviewView(
                content: content,
                onConfirm: {
                    previewingID = nil
                    onPaste(content)
                },
                onCancel: {
                    previewingID = nil
                }
            )
        }
    }
}
