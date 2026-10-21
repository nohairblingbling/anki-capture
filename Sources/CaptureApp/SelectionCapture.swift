import AppKit
import ApplicationServices
import CaptureCore

@MainActor
enum SelectionCapture {
    static var isTrusted: Bool { AXIsProcessTrusted() }
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    static func capture() async throws -> CaptureInput {
        guard isTrusted else { throw CaptureError.invalid("请先在系统设置 → 隐私与安全性 → 辅助功能中允许 Anki Capture。") }
        let front = NSWorkspace.shared.frontmostApplication
        guard front?.bundleIdentifier != Bundle.main.bundleIdentifier else {
            throw CaptureError.invalid("请先回到阅读器选中单词，再按全局快捷键。也可以在这里手动输入。")
        }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        var selected = ""
        var context = ""
        var title = front?.localizedName ?? ""
        if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            let element = unsafeBitCast(focused, to: AXUIElement.self)
            selected = attribute(element, kAXSelectedTextAttribute) ?? ""
            if let full = attribute(element, kAXValueAttribute), full.count <= 6000,
               !selected.isEmpty, full.contains(selected), full != selected {
                context = full
            }
        }
        if let pid = front?.processIdentifier {
            let app = AXUIElementCreateApplication(pid)
            var window: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
               let window, CFGetTypeID(window) == AXUIElementGetTypeID(),
               let value = attribute(unsafeBitCast(window, to: AXUIElement.self), kAXTitleAttribute) {
                title = value
            }
        }
        if selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selected = try await copySelection(expectedPID: front?.processIdentifier)
        }
        return try CaptureInput(text: selected, context: context, source: String(title.prefix(2000)), sourceApp: front?.bundleIdentifier ?? "")
    }
    private static func attribute(_ element: AXUIElement, _ key: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value as? String
    }
    private static func copySelection(expectedPID: pid_t?) async throws -> String {
        let board = NSPasteboard.general
        // Snapshot eagerly; restore only when no subsequent clipboard owner has written.
        let snapshot = board.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        } ?? []
        let previous = board.changeCount
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID else {
            throw CaptureError.invalid("前台应用已切换，请重新选词。")
        }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: false) else {
            throw CaptureError.invalid("无法发送复制快捷键。")
        }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        for _ in 0..<15 {
            try await Task.sleep(for: .milliseconds(60))
            if board.changeCount != previous {
                let copiedAt = board.changeCount
                let text = board.string(forType: .string) ?? ""
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID else {
                    throw CaptureError.invalid("复制期间应用已切换，请重新选词。")
                }
                if board.changeCount == copiedAt {
                    board.clearContents()
                    if !snapshot.isEmpty { board.writeObjects(snapshot) }
                }
                guard !text.isEmpty else { throw CaptureError.invalid("选区不是可复制的文本。扫描 PDF 可先在 PDF Expert 中进行 OCR。") }
                return text
            }
        }
        throw CaptureError.invalid("未读到新选区。请确认选中了文本；也可复制后在窗口中手动添加。")
    }
}
