import SwiftUI

@main
struct PetacoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: SnippetStore
    @StateObject private var historyStore: PasteHistoryStore
    @StateObject private var quickPickShortcutStore: QuickPickShortcutStore
    private let clipboardMonitor: ClipboardMonitor
    private let hotkeyManager: HotkeyManager
    private let quickPickManager: QuickPickManager

    init() {
        let store = SnippetStore()
        let historyStore = PasteHistoryStore()
        self._store = StateObject(wrappedValue: store)
        self._historyStore = StateObject(wrappedValue: historyStore)
        let quickPickShortcutStore = QuickPickShortcutStore()
        self._quickPickShortcutStore = StateObject(wrappedValue: quickPickShortcutStore)
        self.clipboardMonitor = ClipboardMonitor(historyStore: historyStore)
        self.hotkeyManager = HotkeyManager(store: store, historyStore: historyStore)
        self.quickPickManager = QuickPickManager(
            store: store,
            historyStore: historyStore,
            shortcutStore: quickPickShortcutStore,
            startsMonitoring: true,
            startsSessionMonitoring: true,
            usesSessionCancelMonitor: false,
            usesOutsideClickMonitor: true
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                store: store,
                historyStore: historyStore,
                quickPickShortcutStore: quickPickShortcutStore,
                hotkeyManager: hotkeyManager
            )
                .navigationTitle("ペタコ")
        }
        .windowResizability(.contentSize)
    }
}
