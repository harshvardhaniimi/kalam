import SwiftUI
import AppKit
import Combine

@main
struct KalamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Hidden main window (we use menu bar instead)
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var mainWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: AppBrand.displayName)
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 400, height: 500)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: MainView()
                .environmentObject(AppState.shared)
        )

        // Menu bar icon mirrors app state: red while recording, tinted while
        // transcribing — glanceable status without opening the popover.
        AppState.shared.$isRecording
            .combineLatest(AppState.shared.$isProcessing)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording, processing in
                self?.updateStatusIcon(recording: recording, processing: processing)
            }
            .store(in: &cancellables)

        // Initialize app state (downloads model if needed, starts hotkey monitoring)
        Task {
            await AppState.shared.initialize()
        }
    }

    private func updateStatusIcon(recording: Bool, processing: Bool) {
        guard let button = statusItem?.button else { return }

        if recording {
            button.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
            button.contentTintColor = .systemRed
        } else if processing {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Transcribing")
            // Ink purple, matching DesignSystem.Colors.ink
            button.contentTintColor = NSColor(srgbRed: 0.43, green: 0.37, blue: 0.57, alpha: 1.0)
        } else {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: AppBrand.displayName)
            button.contentTintColor = nil
        }
    }

    @objc func togglePopover() {
        if let button = statusItem?.button {
            if popover?.isShown == true {
                popover?.performClose(nil)
            } else {
                popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                // Activate the app
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }

    @MainActor @objc func showMainWindow() {
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = AppBrand.displayName
            window.contentView = NSHostingView(
                rootView: MainWindowView()
                    .environmentObject(AppState.shared)
            )
            mainWindow = window
        }

        mainWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
