import Foundation

// 貼り付けた内容1件分の履歴
struct PasteHistoryItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var content: String
}
