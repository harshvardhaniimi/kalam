import UserNotifications
import AppKit

@MainActor
class NotificationService: ObservableObject {
    static let shared = NotificationService()

    private var notificationsAuthorized: Bool = false

    private init() {
        // Check if we have a proper bundle (required for UNUserNotificationCenter)
        if Bundle.main.bundleIdentifier != nil {
            checkAndRequestPermission()
        }
    }

    private func checkAndRequestPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional:
                    self.notificationsAuthorized = true
                case .notDetermined:
                    self.requestPermission()
                default:
                    self.notificationsAuthorized = false
                }
            }
        }
    }

    private func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                self.notificationsAuthorized = granted
            }
        }
    }

    func showRecordingStarted() {
        // Play system sound (the menu bar icon turning red is the visual cue)
        NSSound.beep()

        // Notification (silent fail if not authorized)
        guard notificationsAuthorized else { return }
        sendNotification(
            identifier: "recording-started",
            title: "Recording Started",
            body: "Speak now... Press Cmd+Shift+Space again to stop"
        )
    }

    func showRecordingStopped() {
        // Play sound
        NSSound(named: "Pop")?.play()

        guard notificationsAuthorized else { return }
        sendNotification(
            identifier: "recording-stopped",
            title: "Recording Stopped",
            body: "Transcribing..."
        )
    }

    func showTranscriptionComplete(text: String) {
        // Play completion sound
        NSSound(named: "Glass")?.play()

        guard notificationsAuthorized else { return }
        sendNotification(
            identifier: "transcription-complete",
            title: "Transcription Complete",
            body: String(text.prefix(100)) + (text.count > 100 ? "..." : "")
        )
    }

    func showError(_ message: String) {
        // Play error sound
        NSSound.beep()
        print("⚠️ \(message)")

        guard notificationsAuthorized else { return }
        sendNotification(
            identifier: "error-\(UUID().uuidString)",
            title: "\(AppBrand.displayName) Error",
            body: message
        )
    }

    private func sendNotification(identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
