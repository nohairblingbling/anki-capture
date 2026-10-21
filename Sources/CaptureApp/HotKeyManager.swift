import AppKit
import SwiftUI
import Carbon
import Observation

@MainActor @Observable
final class HotKeyManager {
    static let shared = HotKeyManager()
    var onCapture: (() -> Void)?
    var recording = false
    var failure: String?
    var display: String
    private var keyCode: UInt32
    private var modifiers: UInt32
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var monitor: Any?
    private init() {
        let defaults = UserDefaults.standard
        keyCode = UInt32(defaults.object(forKey: "captureKeyCode") as? Int ?? 0)
        modifiers = UInt32(defaults.object(forKey: "captureModifiers") as? Int ?? (cmdKey | optionKey | controlKey))
        display = defaults.string(forKey: "captureShortcutDisplay") ?? "⌃⌥⌘A"
    }
    func register() {
        failure = nil
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if handler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
            let callback: EventHandlerUPP = { _, _, data in
                guard let data else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(data).takeUnretainedValue()
                Task { @MainActor in manager.onCapture?() }
                return noErr
            }
            let result = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType,
                                            Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard result == noErr else { failure = "无法注册快捷键监听（\(result)）。"; return }
        }
        let id = EventHotKeyID(signature: OSType(0x41434B59), id: 1)
        let result = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        if result != noErr { failure = "快捷键可能已被其他应用占用，请重新设置（\(result)）。" }
    }
    func beginRecording() {
        guard !recording else { return }
        recording = true; failure = nil
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.endRecording(); return nil }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command) || flags.contains(.option) || flags.contains(.control) else {
                self.failure = "请至少包含 Command、Option 或 Control。"; return nil
            }
            self.keyCode = UInt32(event.keyCode)
            var carbon: UInt32 = 0
            var label = ""
            if flags.contains(.control) { carbon |= UInt32(controlKey); label += "⌃" }
            if flags.contains(.option) { carbon |= UInt32(optionKey); label += "⌥" }
            if flags.contains(.shift) { carbon |= UInt32(shiftKey); label += "⇧" }
            if flags.contains(.command) { carbon |= UInt32(cmdKey); label += "⌘" }
            self.modifiers = carbon
            label += (event.charactersIgnoringModifiers?.uppercased()).flatMap { $0.isEmpty ? nil : $0 } ?? "Key \(event.keyCode)"
            self.display = label
            UserDefaults.standard.set(Int(self.keyCode), forKey: "captureKeyCode")
            UserDefaults.standard.set(Int(carbon), forKey: "captureModifiers")
            UserDefaults.standard.set(label, forKey: "captureShortcutDisplay")
            self.endRecording()
            return nil
        }
    }
    func endRecording() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        recording = false; register()
    }
}

struct ShortcutRecorder: View {
    @State private var manager = HotKeyManager.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("选词快捷键")
                Spacer()
                Button(manager.recording ? "按下快捷键 · Esc 取消" : manager.display) {
                    if manager.recording { manager.endRecording() } else { manager.beginRecording() }
                }.font(.system(.body, design: .monospaced)).accessibilityLabel("设置全局快捷键")
            }
            if let failure = manager.failure { Text(failure).font(.caption).foregroundStyle(.orange) }
        }.onDisappear { if manager.recording { manager.endRecording() } }
    }
}
