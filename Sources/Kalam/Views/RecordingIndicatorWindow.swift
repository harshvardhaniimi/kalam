import SwiftUI
import AppKit

@MainActor
class RecordingIndicatorWindow: NSObject {
    static let shared = RecordingIndicatorWindow()

    private var window: NSWindow?
    private var hostingView: NSHostingView<RecordingIndicatorView>?
    private var positionTimer: Timer?

    private override init() {
        super.init()
    }

    func show() {
        createAndShowWindow()
    }

    func hide() {
        positionTimer?.invalidate()
        positionTimer = nil

        // Fade out animation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.window?.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor [weak self] in
                self?.window?.orderOut(nil)
                self?.window = nil
                self?.hostingView = nil
            }
        })
    }

    private func createAndShowWindow() {
        // Get cursor position
        let mouseLocation = NSEvent.mouseLocation

        // Live view bound to app state: elapsed time + real audio level
        let indicatorView = RecordingIndicatorView(appState: AppState.shared)
        hostingView = NSHostingView(rootView: indicatorView)
        let size = NSSize(width: 190, height: 50)
        hostingView?.frame = NSRect(origin: .zero, size: size)

        // Create borderless, transparent window
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Position near cursor (offset to bottom-right)
        let windowX = mouseLocation.x + 20
        let windowY = mouseLocation.y - 60
        window.setFrameOrigin(NSPoint(x: windowX, y: windowY))

        // Start with 0 alpha for fade in
        window.alphaValue = 0

        self.window = window

        // Show window
        window.orderFront(nil)

        // Fade in animation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 1
        })

        // Update position periodically to follow cursor
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePosition()
            }
        }
    }

    private func updatePosition() {
        guard let window = window else { return }

        let mouseLocation = NSEvent.mouseLocation
        let windowX = mouseLocation.x + 20
        let windowY = mouseLocation.y - 60

        // Smooth position update
        let currentOrigin = window.frame.origin
        let newX = currentOrigin.x + (windowX - currentOrigin.x) * 0.3
        let newY = currentOrigin.y + (windowY - currentOrigin.y) * 0.3

        window.setFrameOrigin(NSPoint(x: newX, y: newY))
    }
}

struct RecordingIndicatorView: View {
    @ObservedObject var appState: AppState
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 10) {
            // Mic icon with pulse
            ZStack {
                // Outer pulse ring
                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .scaleEffect(isPulsing ? 1.3 : 1.0)
                    .opacity(isPulsing ? 0 : 0.5)

                // Inner circle
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.red, Color.red.opacity(0.8)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 18
                        )
                    )
                    .frame(width: 32, height: 32)

                // Mic icon
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }

            // Text
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Recording")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)

                    // Elapsed time, live
                    Text(formattedDuration)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.85))
                }

                // Audio level bars driven by the real input level
                HStack(spacing: 2) {
                    ForEach(0..<5) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 4, height: barHeight(for: i))
                            .animation(.easeInOut(duration: 0.1), value: appState.audioLevel)
                    }
                }
                .frame(height: 12, alignment: .center)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.85))
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
        )
        .onAppear {
            withAnimation(
                Animation.easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: false)
            ) {
                isPulsing = true
            }
        }
    }

    private var formattedDuration: String {
        let total = Int(appState.recordingDuration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let level = CGFloat(appState.audioLevel)
        // Stagger the bars so they read as an equalizer, not a block
        let phase = CGFloat(index) * 0.9
        let variation = (sin(level * 10 + phase) + 1) / 2
        let intensity = min(1.0, level * 0.7 + variation * 0.3 * level)
        return 4 + intensity * 8
    }
}
