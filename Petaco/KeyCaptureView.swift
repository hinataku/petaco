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
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        if isCapturing {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

// 実際にキー入力イベントを受け取るNSView
final class KeyCaptureNSView: NSView {
    var onCapture: ((UInt32, UInt32) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        var mods: UInt32 = 0
        if event.modifierFlags.contains(.command) { mods |= Modifiers.command.rawValue }
        if event.modifierFlags.contains(.shift) { mods |= Modifiers.shift.rawValue }
        if event.modifierFlags.contains(.option) { mods |= Modifiers.option.rawValue }
        if event.modifierFlags.contains(.control) { mods |= Modifiers.control.rawValue }

        // 修飾キーが何も押されていない単独キーは登録させない（誤爆防止）
        guard mods != 0 else { return }

        onCapture?(UInt32(event.keyCode), mods)
    }
}
