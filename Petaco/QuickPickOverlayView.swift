import SwiftUI

// 設定したショートカットで画面中央に表示する一覧オーバーレイ
struct QuickPickOverlayView: View {
    @ObservedObject var manager: QuickPickManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("↑↓ で選択・クリックまたはEnterで貼り付け・他のキーで閉じる")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(manager.entries.enumerated()), id: \.element.id) { index, entry in
                            EntryRow(
                                content: entry.content,
                                isSelected: index == manager.selectedIndex
                            ) {
                                manager.selectAndPaste(at: index)
                            }
                            .id(index)
                        }
                    }
                }
                .onChange(of: manager.selectedIndex) { selectedIndex in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(selectedIndex, anchor: .center)
                    }
                }
                .onChange(of: manager.entries) { _ in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(0, anchor: .top)
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .frame(width: 360)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        .shadow(radius: 20)
    }
}

private struct EntryRow: View {
    let content: String
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(content)
                    .font(.body)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.2) : isHovered ? Color.gray.opacity(0.1) : Color.clear)
        .onHover { inside in
            isHovered = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
