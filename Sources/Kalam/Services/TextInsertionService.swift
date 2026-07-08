import Cocoa
#if !APP_STORE_BUILD
import ApplicationServices
#endif

@MainActor
class TextInsertionService {
    static let shared = TextInsertionService()

    private init() {}

    /// Insert text at the current cursor position in the focused application.
    /// The text is always placed on the clipboard first, so even if the
    /// simulated paste cannot run the user can paste manually with Cmd+V.
    func insertTextAtCursor(_ text: String) {
        copyToClipboard(text)

        #if !APP_STORE_BUILD
        // CGEvent posting is silently discarded by macOS unless this exact
        // binary is trusted for Accessibility. A stale grant (e.g. after the
        // app was rebuilt) also fails silently — so check, don't assume.
        guard AXIsProcessTrusted() else {
            promptForAccessibility()
            NotificationService.shared.showError(
                "Text copied to clipboard — press Cmd+V to paste. To auto-insert, grant Accessibility to \(AppBrand.displayName) in System Settings → Privacy & Security → Accessibility (remove the old entry first if it's already listed)."
            )
            return
        }

        // Small delay to ensure clipboard is set
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.simulatePaste()
        }
        #endif
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    #if !APP_STORE_BUILD
    /// Ask macOS to show the Accessibility permission prompt/panel.
    private func promptForAccessibility() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }

    private func simulatePaste() {
        // Check if there's a frontmost application
        guard NSWorkspace.shared.frontmostApplication != nil else {
            print("No frontmost application")
            return
        }

        // Create Cmd+V key event
        let source = CGEventSource(stateID: .hidSystemState)

        // Key down for Command
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = .maskCommand

        // Key down for V
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        vDown?.flags = .maskCommand

        // Key up for V
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand

        // Key up for Command
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)

        // Post events
        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)

        print("Simulated paste (Cmd+V)")
    }

    func checkAccessibilityPermissions() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options)
    }
    #endif
}
