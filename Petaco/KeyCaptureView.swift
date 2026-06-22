import SwiftUI
import Carbon.HIToolbox

// クリックして好きなキーを押すと、そのキーコード・修飾キーをキャプチャするビュー
struct KeyCaptureView: NSViewRepresentable {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    @Binding var isCapturing: Bool

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onCapture = { code, mods in
            keyCode = code
            modifiers = mods
            isCapturing = false
        }
        view.isCapturing = isCapturing
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.isCapturing = isCapturing
    }
}

// 実際にキー入力イベントを受け取るNSView
final class KeyCaptureNSView: NSView {
    var onCapture: ((UInt32, UInt32) -> Void)?
    private var localKeyMonitor: Any?
    var isCapturing = false {
        didSet {
            if isCapturing {
                becomeFirstResponderWhenPossible()
                startLocalKeyMonitor()
            } else {
                stopLocalKeyMonitor()
            }
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if isCapturing {
            becomeFirstResponderWhenPossible()
        }
    }

    private func becomeFirstResponderWhenPossible() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCapturing else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }
        capture(event)
    }

    private func startLocalKeyMonitor() {
        guard localKeyMonitor == nil else { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.isCapturing else { return event }
            self.capture(event)
            return nil
        }
    }

    private func stopLocalKeyMonitor() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        localKeyMonitor = nil
    }

    private func capture(_ event: NSEvent) {
        var mods: UInt32 = 0
        if event.modifierFlags.contains(.command) { mods |= Modifiers.command.rawValue }
        if event.modifierFlags.contains(.shift) { mods |= Modifiers.shift.rawValue }
        if event.modifierFlags.contains(.option) { mods |= Modifiers.option.rawValue }
        if event.modifierFlags.contains(.control) { mods |= Modifiers.control.rawValue }

        // 修飾キーが何も押されていない単独キーは登録させない（誤爆防止）
        guard mods != 0 else { return }

        isCapturing = false
        onCapture?(UInt32(event.keyCode), mods)
    }

    deinit {
        stopLocalKeyMonitor()
    }
}
