import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

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
    private var statusItemDropView: StatusItemDropView?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: AppBrand.displayName)
            button.action = #selector(togglePopover)
            button.target = self
            button.toolTip = "Click to open \(AppBrand.displayName), or drop an audio file to transcribe it"
            button.setAccessibilityHelp("Drop an audio file here to transcribe it, copy the transcript, and save it to History")

            let dropView = StatusItemDropView(frame: button.bounds)
            dropView.autoresizingMask = [.width, .height]
            dropView.onClick = { [weak self] in
                self?.togglePopover()
            }
            dropView.onAudioFileDrop = { url in
                Task { @MainActor in
                    await AppState.shared.transcribeFile(url: url)
                }
            }
            button.addSubview(dropView)
            statusItemDropView = dropView
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

private final class StatusItemDropView: NSView {
    var onClick: (() -> Void)?
    var onAudioFileDrop: ((URL) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(false)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard audioURL(from: sender.draggingPasteboard) != nil else { return [] }
        setButtonHighlighted(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard audioURL(from: sender.draggingPasteboard) != nil else { return [] }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setButtonHighlighted(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { setButtonHighlighted(false) }
        guard let url = audioURL(from: sender.draggingPasteboard) else { return false }
        onAudioFileDrop?(url)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        setButtonHighlighted(false)
    }

    private func audioURL(from pasteboard: NSPasteboard) -> URL? {
        guard let object = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )?.first as? NSURL else {
            return nil
        }
        let url = object as URL
        return AudioFileLoader.isAudioFile(url) ? url : nil
    }

    private func setButtonHighlighted(_ highlighted: Bool) {
        (superview as? NSButton)?.highlight(highlighted)
    }
}
