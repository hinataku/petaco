import Foundation
import Combine
import Carbon.HIToolbox

struct QuickPickShortcut: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var keyCode: UInt32
    var modifiers: UInt32
}

final class QuickPickShortcutStore: ObservableObject {
    private enum Keys {
        static let shortcuts = "quickPickShortcuts"
        // 旧フォーマットのキー（マイグレーション用）
        static let legacyKeyCode = "quickPickShortcutKeyCode"
        static let legacyModifiers = "quickPickShortcutModifiers"
    }

    @Published var shortcuts: [QuickPickShortcut] { didSet { save() } }
    @Published var isEditing = false

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Keys.shortcuts),
           let decoded = try? JSONDecoder().decode([QuickPickShortcut].self, from: data) {
            shortcuts = decoded
        } else {
            // 旧フォーマット（単一ショートカット）からの移行
            let keyCode = defaults.object(forKey: Keys.legacyKeyCode) as? UInt32 ?? UInt32(kVK_Space)
            let modifiers = defaults.object(forKey: Keys.legacyModifiers) as? UInt32
                ?? (Modifiers.command.rawValue | Modifiers.shift.rawValue)
            shortcuts = [QuickPickShortcut(keyCode: keyCode, modifiers: modifiers)]
            save()
        }
    }

    func add(_ shortcut: QuickPickShortcut) {
        shortcuts.append(shortcut)
    }

    func update(_ shortcut: QuickPickShortcut) {
        if let index = shortcuts.firstIndex(where: { $0.id == shortcut.id }) {
            shortcuts[index] = shortcut
        }
    }

    func delete(_ shortcut: QuickPickShortcut) {
        shortcuts.removeAll { $0.id == shortcut.id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(shortcuts) {
            UserDefaults.standard.set(data, forKey: Keys.shortcuts)
        }
    }
}
