#if !APP_STORE_BUILD
import Cocoa
import Carbon

// Simple file logger for debugging
private func logToFile(_ message: String) {
    let logPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("kalam-hotkey.log")
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logPath.path) {
            if let handle = try? FileHandle(forWritingTo: logPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: logPath)
        }
    }
}

@MainActor
class GlobalHotkeyManager: ObservableObject {
    @Published var isEnabled = true

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    // Hotkey: Cmd+Shift+Space
    private let keyCode: UInt32 = 49  // Space key
    private let modifiers: UInt32 = UInt32(cmdKey | shiftKey)  // Cmd+Shift

    /// Fired when the hotkey goes down / comes back up. AppState combines
    /// the two into tap-to-toggle vs hold-to-talk semantics.
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?

    // Static reference for the C callback
    private static var sharedInstance: GlobalHotkeyManager?

    init() {
        GlobalHotkeyManager.sharedInstance = self
        logToFile("GlobalHotkeyManager initialized (Cmd+Shift+Space)")
        print("GlobalHotkeyManager initialized (Cmd+Shift+Space)")
    }

    func startMonitoring() {
        guard isEnabled else {
            print("Hotkey monitoring disabled")
            return
        }

        // Don't register twice
        guard hotKeyRef == nil else {
            print("Hotkey already registered")
            return
        }

        // Install event handler for both press and release (hold-to-talk)
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                let kind = GetEventKind(event)
                if kind == UInt32(kEventHotKeyPressed) {
                    logToFile("🎉 Hotkey down")
                    Task { @MainActor in
                        GlobalHotkeyManager.sharedInstance?.onHotkeyDown?()
                    }
                } else if kind == UInt32(kEventHotKeyReleased) {
                    Task { @MainActor in
                        GlobalHotkeyManager.sharedInstance?.onHotkeyUp?()
                    }
                }
                return noErr
            },
            2,
            &eventTypes,
            nil,
            &eventHandler
        )

        guard status == noErr else {
            print("Failed to install event handler: \(status)")
            NotificationService.shared.showError("Could not set up the global hotkey (error \(status)). Use the menu bar icon to record.")
            return
        }

        // Register the hotkey
        let hotkeyID = EventHotKeyID(signature: OSType(0x4B4C4D00), id: 1)  // 'KLM\0'

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus == noErr {
            logToFile("✅ Global hotkey registered: Cmd+Shift+Space")
            print("✅ Global hotkey registered: Cmd+Shift+Space")
        } else {
            logToFile("Failed to register hotkey: \(registerStatus)")
            print("Failed to register hotkey: \(registerStatus)")
            NotificationService.shared.showError("Could not register Cmd+Shift+Space — another app may already use it. Use the menu bar icon to record.")
            // Clean up event handler if hotkey registration failed
            if let handler = eventHandler {
                RemoveEventHandler(handler)
                eventHandler = nil
            }
        }
    }

    func stopMonitoring() {
        if let hotKey = hotKeyRef {
            UnregisterEventHotKey(hotKey)
            hotKeyRef = nil
            print("Hotkey unregistered")
        }

        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    deinit {
        if let hotKey = hotKeyRef {
            UnregisterEventHotKey(hotKey)
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
        // Note: Can't clear sharedInstance here due to actor isolation
        // The singleton pattern via AppState.shared ensures proper lifecycle
    }
}

#else

// App Store build: no-op stub (Carbon global hotkeys not allowed in sandbox)
import Foundation

@MainActor
class GlobalHotkeyManager: ObservableObject {
    @Published var isEnabled = false

    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?

    init() {
        print("GlobalHotkeyManager disabled (App Store build)")
    }

    func startMonitoring() {}
    func stopMonitoring() {}
}

#endif
