import SwiftUI
import Carbon.HIToolbox

struct QuickPickShortcutEditView: View {
    @ObservedObject var store: QuickPickShortcutStore
    let editingShortcut: QuickPickShortcut? // nil = 追加モード
    let onDismiss: () -> Void

    @State private var keyCode: UInt32
    @State private var modifiers: UInt32
    @State private var isCapturing: Bool

    init(store: QuickPickShortcutStore, editingShortcut: QuickPickShortcut? = nil, onDismiss: @escaping () -> Void) {
        self.store = store
        self.editingShortcut = editingShortcut
        self.onDismiss = onDismiss
        _keyCode = State(initialValue: editingShortcut?.keyCode ?? UInt32(kVK_Space))
        _modifiers = State(initialValue: editingShortcut?.modifiers ?? (Modifiers.command.rawValue | Modifiers.shift.rawValue))
        // 追加時は即キャプチャ開始、編集時は現在のキーを表示してから待機
        _isCapturing = State(initialValue: editingShortcut == nil)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(editingShortcut == nil ? "履歴ショートカットを追加" : "履歴ショートカットを変更")
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

            KeyCaptureView(
                keyCode: $keyCode,
                modifiers: $modifiers,
                isCapturing: $isCapturing
            )
            .frame(width: 1, height: 1)

            HStack {
                Button("キャンセル", action: onDismiss)
                Spacer()
                Button("入力し直す") {
                    isCapturing = false
                    DispatchQueue.main.async { isCapturing = true }
                }
                Button(editingShortcut == nil ? "追加" : "保存") {
                    if var updated = editingShortcut {
                        updated.keyCode = keyCode
                        updated.modifiers = modifiers
                        store.update(updated)
                    } else {
                        store.add(QuickPickShortcut(keyCode: keyCode, modifiers: modifiers))
                    }
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onDisappear {
            store.isEditing = false
        }
    }

    private var shortcutLabel: String {
        Modifiers(rawValue: modifiers).shortcutLabel(keyCode: keyCode)
    }
}
