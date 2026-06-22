import Foundation
import Combine
import ServiceManagement

// 「ログイン時に自動起動」のON/OFFを管理する
// macOS 13以降の SMAppService を使用（Xcode直接ビルドのアプリでも動作する）
final class LaunchAtLoginManager: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            guard !isUpdatingFromSystem else { return }
            apply(isEnabled)
        }
    }

    private var isUpdatingFromSystem = false

    init() {
        // メインスレッドをブロックしないよう、まず false で初期化してから非同期で更新する
        self.isEnabled = false
        Task.detached(priority: .utility) { [weak self] in
            let enabled = SMAppService.mainApp.status == .enabled
            await MainActor.run { [weak self] in
                self?.isUpdatingFromSystem = true
                self?.isEnabled = enabled
                self?.isUpdatingFromSystem = false
            }
        }
    }

    private func apply(_ enabled: Bool) {
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try await SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                // 失敗した場合は表示状態をシステムの実際の状態に戻す
                let current = SMAppService.mainApp.status == .enabled
                await MainActor.run { [weak self] in
                    self?.isUpdatingFromSystem = true
                    self?.isEnabled = current
                    self?.isUpdatingFromSystem = false
                }
            }
        }
    }

    // ウィンドウを開いたときなど、システム側の状態とズレていないか再確認する
    func refresh() {
        Task.detached(priority: .utility) { [weak self] in
            let enabled = SMAppService.mainApp.status == .enabled
            await MainActor.run { [weak self] in
                self?.isUpdatingFromSystem = true
                self?.isEnabled = enabled
                self?.isUpdatingFromSystem = false
            }
        }
    }
}
