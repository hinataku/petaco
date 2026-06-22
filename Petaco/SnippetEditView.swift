import SwiftUI

// 定型文の新規作成・編集用のシート
struct SnippetEditView: View {
    @ObservedObject var store: SnippetStore
    var onSaved: () -> Void
    var onDismiss: () -> Void

    @State var snippet: Snippet
    @State private var isCapturingKey = false
    let isNew: Bool

    var body: some View {
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

                    Button(isCapturingKey ? "キーを押してください..." : "キーを変更") {
                        isCapturingKey = true
                    }

                    // キャプチャ中だけ、キー入力を受け付ける透明ビューを重ねる
                    if isCapturingKey {
                        KeyCaptureView(keyCode: $snippet.keyCode,
                                       modifiers: $snippet.modifiers,
                                       isCapturing: $isCapturingKey)
                            .frame(width: 1, height: 1)
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
        .padding(20)
        .frame(width: 420, height: 320)
    }

    private var currentShortcutDisplay: String {
        let mods = Modifiers(rawValue: snippet.modifiers)
        return mods.displaySymbols + KeyCodeMap.char(for: snippet.keyCode)
    }
}
