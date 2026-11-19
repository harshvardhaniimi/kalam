#include "notifier.h"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QFile>
#include <QProcess>
#include <QStandardPaths>
#include <QVariantMap>

void Notifier::info(const QString &title, const QString &body) {
    notify(title, body, 1);
}

void Notifier::error(const QString &message) {
    emit errorShown(message);
    cue(Cue::Error);
    notify(tr("Kalam"), message, 2);
}

void Notifier::notify(const QString &title, const QString &body, int urgency) {
    if (m_muted)
        return;
    QDBusInterface notifications("org.freedesktop.Notifications", "/org/freedesktop/Notifications",
                                 "org.freedesktop.Notifications", QDBusConnection::sessionBus());
    if (!notifications.isValid())
        return;
    // Reusing the id replaces Kalam's previous banner rather than stacking.
    const QDBusReply<uint> reply = notifications.call(
        "Notify", "Kalam", m_lastId, "kalam", title, body, QStringList{},
        QVariantMap{{"urgency", QVariant::fromValue(uchar(urgency))}, {"desktop-entry", "kalam"}}, 6000);
    if (reply.isValid())
        m_lastId = reply.value();
}

void Notifier::cue(Cue cue) {
    if (!m_sounds || m_muted)
        return;
    static const QString player = QStandardPaths::findExecutable("pw-play");
    const char *name = cue == Cue::Start ? "message" : cue == Cue::Stop ? "audio-volume-change"
                     : cue == Cue::Done ? "complete" : "dialog-warning";
    const QString file = QString("/usr/share/sounds/freedesktop/stereo/%1.oga").arg(name);
    if (!player.isEmpty() && QFile::exists(file))
        QProcess::startDetached(player, {"--volume", "0.35", file});
}
