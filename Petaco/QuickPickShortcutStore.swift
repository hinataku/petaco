import Foundation
import Combine
import Carbon.HIToolbox

// コピー履歴のクイック選択ショートカットを保存する。
final class QuickPickShortcutStore: ObservableObject {
    private enum Keys {
        static let keyCode = "quickPickShortcutKeyCode"
        static let modifiers = "quickPickShortcutModifiers"
    }

    @Published var keyCode: UInt32 { didSet { save() } }
    @Published var modifiers: UInt32 { didSet { save() } }

    init() {
        let defaults = UserDefaults.standard
        self.keyCode = defaults.object(forKey: Keys.keyCode) as? UInt32 ?? UInt32(kVK_Space)
        self.modifiers = defaults.object(forKey: Keys.modifiers) as? UInt32
            ?? (Modifiers.command.rawValue | Modifiers.shift.rawValue)
    }

    private func save() {
        UserDefaults.standard.set(keyCode, forKey: Keys.keyCode)
        UserDefaults.standard.set(modifiers, forKey: Keys.modifiers)
    }
}
