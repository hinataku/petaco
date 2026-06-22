import SwiftUI

// 長押し時に表示する、貼り付け内容のプレビューポップオーバー
struct PastePreviewView: View {
    let content: String
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("貼り付け内容のプレビュー")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView {
                Text(content)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)

            HStack {
                Spacer()
                Button("キャンセル") { onCancel() }
                Button("貼り付け") { onConfirm() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 280)
    }
}
