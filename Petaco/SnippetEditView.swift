import SwiftUI

// 定型文の新規作成・編集用のシート
struct SnippetEditView: View {
    @ObservedObject var store: SnippetStore
    var onSaved: () -> Void
    var onDismiss: () -> Void
    var onKeyCaptureChanged: (Bool) -> Void

    @State var snippet: Snippet
    @State private var isShowingKeyCaptureDialog = false
    let isNew: Bool

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(isNew ? "定型文を追加" : "定型文を編集")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 4) {
                    Text("貼り付ける内容")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                    TextEditor(text: $snippet.content)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(height: 120)
                        .background(Color(nsColor: .textBackgroundColor))
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.3))
                        }
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text("ショートカットキー")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Text(currentShortcutDisplay)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(6)

                        Button("キーを変更") {
                            onKeyCaptureChanged(true)
                            isShowingKeyCaptureDialog = true
                        }
                    }
                }

                Spacer()

                HStack {
                    Spacer()
                    Button("キャンセル") { onDismiss() }
                    Button(isNew ? "追加" : "保存") {
                        if isNew {
                            store.snippets.append(snippet)
                            store.save()
                        } else {
                            store.update(snippet)
                        }
                        onSaved()
                        onDismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(snippet.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if isShowingKeyCaptureDialog {
                SnippetShortcutCaptureDialog(
                    keyCode: $snippet.keyCode,
                    modifiers: $snippet.modifiers,
                    onDismiss: {
                        onKeyCaptureChanged(false)
                        isShowingKeyCaptureDialog = false
                    }
                )
            }
        }
        .padding(20)
        .frame(width: 420, height: 320)
        .onDisappear {
            onKeyCaptureChanged(false)
        }
    }

    private var currentShortcutDisplay: String {
        let mods = Modifiers(rawValue: snippet.modifiers)
        return mods.displaySymbols + KeyCodeMap.char(for: snippet.keyCode)
    }
}

private struct SnippetShortcutCaptureDialog: View {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    let onDismiss: () -> Void

    @State private var draftKeyCode: UInt32
    @State private var draftModifiers: UInt32
    @State private var isCapturing = true

    init(keyCode: Binding<UInt32>, modifiers: Binding<UInt32>, onDismiss: @escaping () -> Void) {
        _keyCode = keyCode
        _modifiers = modifiers
        self.onDismiss = onDismiss
        _draftKeyCode = State(initialValue: keyCode.wrappedValue)
        _draftModifiers = State(initialValue: modifiers.wrappedValue)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Text("ショートカットキーを変更")
                    .font(.headline)
                Text(isCapturing ? "ショートカットキーを押してください" : "入力されたショートカット")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(shortcutLabel)
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.gray.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                KeyCaptureView(keyCode: $draftKeyCode, modifiers: $draftModifiers, isCapturing: $isCapturing)
                    .frame(width: 1, height: 1)
                HStack {
                    Button("キャンセル", action: onDismiss)
                    Spacer()
                    Button("入力し直す") {
                        isCapturing = false
                        DispatchQueue.main.async { isCapturing = true }
                    }
                    Button("保存") {
                        keyCode = draftKeyCode
                        modifiers = draftModifiers
                        onDismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 370)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 20)
        }
    }

    private var shortcutLabel: String {
        Modifiers(rawValue: draftModifiers).displaySymbols + KeyCodeMap.char(for: draftKeyCode)
    }
}
