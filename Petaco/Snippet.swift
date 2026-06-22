import Foundation
import Carbon.HIToolbox

// 1つの定型文を表すモデル
struct Snippet: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var content: String      // 実際に貼り付けられるテキスト
    var keyCode: UInt32      // ショートカットキーのキーコード (例: "1"のキーコード)
    var modifiers: UInt32    // 修飾キー (Cmdなど) のフラグ

    // デフォルトは Cmd + Shift（Cmd + 数字のアプリ標準ショートカットとの衝突を避ける）
    static let defaultModifiers: UInt32 = Modifiers.command.rawValue | Modifiers.shift.rawValue
}

// 修飾キーをビットフラグで管理（Cmd, Shift, Option, Controlの組み合わせを許可）
struct Modifiers: OptionSet, Codable {
    let rawValue: UInt32

    static let command = Modifiers(rawValue: 1 << 0)
    static let shift   = Modifiers(rawValue: 1 << 1)
    static let option  = Modifiers(rawValue: 1 << 2)
    static let control = Modifiers(rawValue: 1 << 3)

    // 表示用の文字列 (例: "⌘⇧1")
    var displaySymbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }

    // CarbonのグローバルホットキーAPIへ渡す修飾キーフラグへ変換する。
    // rawValueは保存用の独自値なので、そのままRegisterEventHotKeyには渡せない。
    var carbonHotKeyModifiers: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.control) { flags |= UInt32(controlKey) }
        return flags
    }
}
