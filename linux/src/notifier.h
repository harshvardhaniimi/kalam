#pragma once

#include <QObject>

// Desktop notifications and sound cues. Every failure reaches the user
// through here; nothing fails silently.
class Notifier : public QObject {
    Q_OBJECT

public:
    enum class Cue { Start, Stop, Done, Error };

    explicit Notifier(QObject *parent = nullptr) : QObject(parent) {}

    void setSoundsEnabled(bool enabled) { m_sounds = enabled; }
    void setMuted(bool muted) { m_muted = muted; }

    void info(const QString &title, const QString &body);
    void error(const QString &message);
    void cue(Cue cue);

signals:
    // Mirrors the last error into the window.
    void errorShown(const QString &message);

private:
    void notify(const QString &title, const QString &body, int urgency);

    bool m_sounds = true;
    // One-shot command-line runs print instead of raising notifications.
    bool m_muted = false;
    uint m_lastId = 0;
};
