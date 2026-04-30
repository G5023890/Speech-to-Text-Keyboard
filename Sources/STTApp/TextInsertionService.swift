import AppKit
import ApplicationServices
import Foundation

@MainActor
final class TextInsertionService {
    func insert(_ text: String) throws {
        guard AXIsProcessTrusted() else {
            throw TextInsertionError.accessibilityNotTrusted
        }

        let pasteboard = NSPasteboard.general
        let previousItems = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        sendPasteShortcut()

        if let previousItems {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                pasteboard.clearContents()
                pasteboard.writeObjects(previousItems)
            }
        }
    }

    private func sendPasteShortcut() {
        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: KeyCode.v, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: KeyCode.v, keyDown: false)
        else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

enum TextInsertionError: LocalizedError {
    case accessibilityNotTrusted

    var errorDescription: String? {
        "Accessibility permission is required to insert text into the active app."
    }
}

private enum KeyCode {
    static let v: CGKeyCode = 9
}
