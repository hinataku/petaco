import SwiftUI

// 通常クリックで即時貼り付け、長押しでプレビュー表示する貼り付けボタン
struct PasteButton: View {
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
