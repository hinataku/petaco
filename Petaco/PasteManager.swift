import Foundation
import AppKit
import UserNotifications

// 指定テキストを一時的にクリップボードへ置き、対象アプリへ自動ペーストする。
enum PasteManager {
    /// ペタコのウィンドウをクリックすると、ペタコ自身が最前面になります。
    /// クリック前に操作していたアプリを記録しておき、そこを貼り付け先にします。
    private static var lastExternalApplication: NSRunningApplication?
    private static var activationObserver: NSObjectProtocol?
    private static var hasRequestedAccessibilityPermission = false

    static func startTrackingPasteTarget() {
        guard activationObserver == nil else { return }

        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            logFocusChange("Activated", application: application)
            rememberExternalApplication(application)
        }
        // ペタコをクリックして前面化する直前、貼り付け先アプリは非アクティブになる。
        // この通知も記録することで、起動直後の最初のクリックでも貼り付け先を失わない。
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            logFocusChange("Deactivated", application: application)
            rememberExternalApplication(application)
        }
    }

    private static func rememberExternalApplication(_ application: NSRunningApplication?) {
        guard let application,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !application.isTerminated else { return }
        lastExternalApplication = application
    }

    private static func logFocusChange(_ action: String, application: NSRunningApplication?) {
        let name = application?.localizedName ?? "Unknown"
        let pid = application?.processIdentifier ?? 0
        PetacoLog.focus.notice("\(action, privacy: .public) app=\(name, privacy: .public) pid=\(pid, privacy: .public)")
    }

    // onSuccess: 実際にペースト操作を送信できたときに呼ばれる（履歴記録用）
    static func paste(
        text: String,
        restorePreviousApplication: Bool = true,
        targetApplication: NSRunningApplication? = nil,
        onSuccess: ((String) -> Void)? = nil
    ) {
        let accessibilityTrusted = AXIsProcessTrusted()
        PetacoLog.paste.notice("Paste requested, textLength=\(text.count, privacy: .public), restorePreviousApplication=\(restorePreviousApplication, privacy: .public), accessibilityTrusted=\(accessibilityTrusted, privacy: .public)")
        guard accessibilityTrusted else {
            requestAccessibilityPermissionOnce()
            return
        }
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        ClipboardMonitor.ignore(changeCount: pasteboard.changeCount)

        // ウィンドウ内ボタンからの実行時だけ、直前のアプリへ戻す。
        // グローバルホットキーでは、押した時点の前面アプリへそのまま送る。
        let applicationToRestore: NSRunningApplication?
        if let targetApplication, !targetApplication.isTerminated {
            // クイック選択のNSPanelは非アクティブなので、貼り付け先のフォーカスは
            // すでに維持されている。activateすると余計なアプリ切替待ちが発生するため、
            // プロセスへの直接送信だけを行う。
            applicationToRestore = nil
        } else if restorePreviousApplication {
            applicationToRestore = lastExternalApplication
            lastExternalApplication?.activate(options: [.activateIgnoringOtherApps])
        } else {
            applicationToRestore = nil
        }
        let restoreApp = applicationToRestore
        let targetApp = targetApplication
        // ホットキー経由は restorePreviousApplication=false なので applicationToRestore が nil になる。
        // lastExternalApplication を fallback として使い、Windows App 等の検出を確実にする。
        let detectionApp = targetApp ?? restoreApp ?? lastExternalApplication
        let clipboardOnly = Self.needsCtrlV(detectionApp)

        PetacoLog.paste.notice("[paste] detectionApp=\(detectionApp?.localizedName ?? "nil", privacy: .public) bundleID=\(detectionApp?.bundleIdentifier ?? "nil", privacy: .public) clipboardOnly=\(clipboardOnly, privacy: .public)")

        if clipboardOnly {
            // RDP/VMなどキー合成が効かない環境はクリップボードに残す（復元しない）
            // ユーザーが手動でCtrl+Vすれば貼り付けられる
            restoreApp?.activate(options: [.activateIgnoringOtherApps])
            onSuccess?(text)
            return
        }

        DispatchQueue.main.async {
            let source = CGEventSource(stateID: .hidSystemState)
            let modKeyCode: CGKeyCode = 0x37  // left Command
            let modDown = CGEvent(keyboardEventSource: source, virtualKey: modKeyCode, keyDown: true)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            let modUp   = CGEvent(keyboardEventSource: source, virtualKey: modKeyCode, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags   = .maskCommand

            if let targetApp, !targetApp.isTerminated {
                modDown?.postToPid(targetApp.processIdentifier)
                keyDown?.postToPid(targetApp.processIdentifier)
                keyUp?.postToPid(targetApp.processIdentifier)
                modUp?.postToPid(targetApp.processIdentifier)
                PetacoLog.paste.notice("[paste] sent Cmd+V via postToPid=\(targetApp.processIdentifier, privacy: .public)")
            } else {
                modDown?.post(tap: .cghidEventTap)
                keyDown?.post(tap: .cghidEventTap)
                keyUp?.post(tap: .cghidEventTap)
                modUp?.post(tap: .cghidEventTap)
                PetacoLog.paste.notice("[paste] sent Cmd+V via cghidEventTap")
            }
            restoreApp?.activate(options: [.activateIgnoringOtherApps])
            onSuccess?(text)
        }

        // 既存のクリップボード内容はペースト後に復元する。
        if let previousContents {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pasteboard.clearContents()
                pasteboard.setString(previousContents, forType: .string)
                ClipboardMonitor.ignore(changeCount: pasteboard.changeCount)
            }
        }
    }


    // RDP・VMなどキー合成が効かない環境の検出
    private static let ctrlVBundleIDs: Set<String> = [
        "com.microsoft.rdc.macos",   // Windows App (Microsoft Remote Desktop)
        "com.parallels.desktop",     // Parallels Desktop
        "com.vmware.fusion",         // VMware Fusion
        "com.utmapp.UTM",            // UTM
    ]

    private static func needsCtrlV(_ app: NSRunningApplication?) -> Bool {
        guard let bundleID = app?.bundleIdentifier else { return false }
        return ctrlVBundleIDs.contains(bundleID)
    }

    private static func requestAccessibilityPermissionOnce() {
        guard !hasRequestedAccessibilityPermission else { return }
        hasRequestedAccessibilityPermission = true
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        PetacoLog.paste.notice("Requested macOS accessibility permission")
    }
}
