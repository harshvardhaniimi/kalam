#include "portalfilepicker.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDir>
#include <QRandomGenerator>
#include <QStandardPaths>

namespace {
struct FilterRule {
    uint type;
    QString pattern;
};
using FilterRules = QList<FilterRule>;

struct FileFilter {
    QString name;
    FilterRules rules;
};
using FileFilters = QList<FileFilter>;

QDBusArgument &operator<<(QDBusArgument &argument, const FilterRule &rule) {
    argument.beginStructure();
    argument << rule.type << rule.pattern;
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, FilterRule &rule) {
    argument.beginStructure();
    argument >> rule.type >> rule.pattern;
    argument.endStructure();
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const FileFilter &filter) {
    argument.beginStructure();
    argument << filter.name << filter.rules;
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, FileFilter &filter) {
    argument.beginStructure();
    argument >> filter.name >> filter.rules;
    argument.endStructure();
    return argument;
}

const char *portalService = "org.freedesktop.portal.Desktop";
const char *portalPath = "/org/freedesktop/portal/desktop";

QByteArray pathBytes(const QString &path) {
    QByteArray bytes = path.toUtf8();
    bytes.append('\0');
    return bytes;
}
}

PortalFilePicker::PortalFilePicker(QObject *parent) : FilePicker(parent) {
    qDBusRegisterMetaType<FilterRule>();
    qDBusRegisterMetaType<FilterRules>();
    qDBusRegisterMetaType<FileFilter>();
    qDBusRegisterMetaType<FileFilters>();
}

void PortalFilePicker::openAudio() {
    const FileFilter media{tr("Audio and video files"),
                           {{1, "audio/*"}, {1, "video/*"}, {0, "*.mp3"}, {0, "*.wav"}, {0, "*.m4a"},
                            {0, "*.flac"}, {0, "*.ogg"}, {0, "*.opus"}, {0, "*.mp4"}, {0, "*.mkv"}, {0, "*.webm"}}};
    QVariantMap options;
    options.insert("accept_label", tr("Transcribe"));
    options.insert("modal", true);
    options.insert("multiple", false);
    options.insert("filters", QVariant::fromValue(FileFilters{media, {tr("All files"), {{0, "*"}}}}));
    options.insert("current_filter", QVariant::fromValue(media));
    request("OpenFile", tr("Transcribe an Audio File"), options, Action::Open);
}

void PortalFilePicker::saveText(const QString &suggestedName) {
    const QString documents = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    QVariantMap options;
    options.insert("accept_label", tr("Export"));
    options.insert("modal", true);
    options.insert("current_name", suggestedName);
    options.insert("current_folder", pathBytes(QDir(documents).exists() ? documents : QDir::homePath()));
    request("SaveFile", tr("Export Transcription"), options, Action::Save);
}

void PortalFilePicker::request(const QString &method, const QString &title, QVariantMap options, Action action) {
    clearPending();
    const int generation = ++m_generation;

    // The portal answers on a request object whose path is derived from our
    // bus name and this token; subscribe before calling so a fast reply
    // can't be missed.
    const QString token = QString("kalam_%1").arg(QRandomGenerator::global()->generate());
    options.insert("handle_token", token);
    QString sender = QDBusConnection::sessionBus().baseService().mid(1);
    sender.replace('.', '_');
    m_pendingPath = QString("/org/freedesktop/portal/desktop/request/%1/%2").arg(sender, token);
    m_pendingAction = action;
    QDBusConnection::sessionBus().connect(portalService, m_pendingPath, "org.freedesktop.portal.Request",
                                          "Response", this, SLOT(handleResponse(uint, QVariantMap)));

    QDBusMessage call = QDBusMessage::createMethodCall(portalService, portalPath,
                                                       "org.freedesktop.portal.FileChooser", method);
    call << QString() << title << options;
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(call), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, generation] {
        watcher->deleteLater();
        const QDBusPendingReply<QDBusObjectPath> reply = *watcher;
        if (generation != m_generation || !reply.isError())
            return;
        clearPending();
        emit failed(tr("The file dialog could not be opened: %1").arg(reply.error().message()));
    });
}

void PortalFilePicker::clearPending() {
    if (!m_pendingPath.isEmpty())
        QDBusConnection::sessionBus().disconnect(portalService, m_pendingPath, "org.freedesktop.portal.Request",
                                                 "Response", this, SLOT(handleResponse(uint, QVariantMap)));
    m_pendingPath.clear();
    m_pendingAction = Action::None;
}

void PortalFilePicker::handleResponse(uint response, const QVariantMap &results) {
    const Action action = m_pendingAction;
    clearPending();
    // 1 is the user cancelling, which needs no message.
    if (response != 0)
        return;
    const QStringList uris = results.value("uris").toStringList();
    if (uris.isEmpty())
        return;
    if (action == Action::Open)
        emit openSelected(QUrl(uris.first()));
    else if (action == Action::Save)
        emit saveSelected(QUrl(uris.first()));
}
