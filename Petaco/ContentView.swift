import SwiftUI

struct ContentView: View {
    @ObservedObject var store: SnippetStore
    @ObservedObject var historyStore: PasteHistoryStore
    @ObservedObject var quickPickShortcutStore: QuickPickShortcutStore
    @StateObject private var launchAtLogin = LaunchAtLoginManager()
    let hotkeyManager: HotkeyManager

    @State private var editingSnippet: Snippet?
    @State private var isAddingNew = false
    @State private var editingSnippetShortcut: Snippet?
    @State private var draftShortcutKeyCode: UInt32 = 0
    @State private var draftShortcutModifiers: UInt32 = 0
    @State private var isAddingQuickPickShortcut = false
    @State private var editingQuickPickShortcut: QuickPickShortcut?
    @State private var duplicateWarning: String?
    @State private var isConfirmingClearAll = false

    // 長押しでプレビューを出す対象のID（nilなら非表示）
    @State private var previewingID: UUID?

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
            } else if editingSnippetShortcut != nil {
                snippetShortcutOverlay
            } else if isAddingQuickPickShortcut || editingQuickPickShortcut != nil {
                quickPickShortcutOverlay
            }
        }
        .onAppear {
            hotkeyManager.reloadAllHotkeys()
            checkDuplicates()
        }
        .alert("コピー履歴をすべて削除しますか？", isPresented: $isConfirmingClearAll) {
            Button("すべて削除", role: .destructive) {
                historyStore.clearAll()
            }
            Button("キャンセル", role: .cancel) {}
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
                Toggle("自動的に立ち上げる", isOn: $launchAtLogin.isEnabled)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .onAppear {
                        launchAtLogin.refresh()
                    }
            }
            .padding()

            HStack {
                Text("定型文貼り付け")
                    .font(.headline)
                Spacer()
                Button {
                    isAddingNew = true
                } label: {
                    Label("追加", systemImage: "plus")
                }
            }
            .padding(.horizontal)
            .padding(.bottom)

            if let warning = duplicateWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            List {
                ForEach(store.snippets) { snippet in
                    HStack(spacing: 8) {
                        Button {
                            editingSnippetShortcut = snippet
                            draftShortcutKeyCode = snippet.keyCode
                            draftShortcutModifiers = snippet.modifiers
                            hotkeyManager.suspendAllHotkeys()
                        } label: {
                            Text(shortcutLabel(for: snippet))
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.15))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button {
                            editingSnippet = snippet
                        } label: {
                            Text(snippet.content)
                                .font(.body)
                                .lineLimit(1)
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        PasteButton(id: snippet.id, content: snippet.content,
                                    onPaste: pasteFromWindow,
                                    previewingID: $previewingID)

                        Button {
                            store.delete(snippet)
                            hotkeyManager.reloadAllHotkeys()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    // MARK: - 右側: 貼り付け履歴
    private var historySection: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("履歴貼り付け")
                        .font(.headline)
                    Spacer()
                    Button {
                        quickPickShortcutStore.isEditing = true
                        isAddingQuickPickShortcut = true
                    } label: {
                        Label("追加", systemImage: "plus")
                    }
                }

                ForEach(quickPickShortcutStore.shortcuts) { shortcut in
                    HStack(spacing: 6) {
                        Button {
                            editingQuickPickShortcut = shortcut
                            quickPickShortcutStore.isEditing = true
                        } label: {
                            Text(Modifiers(rawValue: shortcut.modifiers).shortcutLabel(keyCode: shortcut.keyCode))
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.15))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button {
                            quickPickShortcutStore.delete(shortcut)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, 4)

            HStack {
                Text("コピー履歴")
                    .font(.headline)
                Spacer()
                if !historyStore.items.isEmpty {
                    Button("すべて削除") {
                        isConfirmingClearAll = true
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
                ScrollViewReader { proxy in
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
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .onChange(of: historyStore.items.first?.id) { firstID in
                        if let firstID {
                            proxy.scrollTo(firstID, anchor: .top)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }

    // 一覧・履歴の貼り付けボタンから実行する。コピー履歴への記録はClipboardMonitorが担当する。
    private func pasteFromWindow(_ text: String) {
        PasteManager.paste(text: text)
    }

    private func shortcutLabel(for snippet: Snippet) -> String {
        Modifiers(rawValue: snippet.modifiers).shortcutLabel(keyCode: snippet.keyCode)
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
                onKeyCaptureChanged: { isCapturing in
                    if isCapturing {
                        hotkeyManager.suspendAllHotkeys()
                    } else {
                        hotkeyManager.reloadAllHotkeys()
                    }
                },
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

    private var snippetShortcutOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            SnippetShortcutCaptureDialog(
                keyCode: $draftShortcutKeyCode,
                modifiers: $draftShortcutModifiers,
                onDismiss: {
                    if var s = editingSnippetShortcut {
                        s.keyCode = draftShortcutKeyCode
                        s.modifiers = draftShortcutModifiers
                        store.update(s)
                        checkDuplicates()
                    }
                    editingSnippetShortcut = nil
                    hotkeyManager.reloadAllHotkeys()
                }
            )
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 20)
        }
    }

    private var quickPickShortcutOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            QuickPickShortcutEditView(
                store: quickPickShortcutStore,
                editingShortcut: editingQuickPickShortcut,
                onDismiss: {
                    quickPickShortcutStore.isEditing = false
                    isAddingQuickPickShortcut = false
                    editingQuickPickShortcut = nil
                }
            )
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 20)
        }
    }
}
