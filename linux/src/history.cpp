#include "history.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QSaveFile>
#include <QStandardPaths>
#include <QVariantMap>

namespace {
QJsonObject toJson(const Transcription &entry) {
    QJsonObject object{{"id", entry.id},
                       {"text", entry.text},
                       {"date", entry.date.toUTC().toString(Qt::ISODate)},
                       {"duration", entry.duration},
                       {"language", entry.language}};
    if (!entry.sourceFile.isEmpty())
        object.insert("sourceFile", entry.sourceFile);
    return object;
}
}

History::History(const QString &path, QObject *parent)
    : QObject(parent),
      m_path(path.isEmpty()
                 ? QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/kalam/history.json"
                 : path) {
    load();
}

QString History::formatDuration(double seconds) {
    const int total = int(seconds);
    return QString("%1:%2").arg(total / 60, 2, 10, QChar('0')).arg(total % 60, 2, 10, QChar('0'));
}

void History::load() {
    QFile file(m_path);
    if (!file.open(QIODevice::ReadOnly))
        return;
    for (const auto &value : QJsonDocument::fromJson(file.readAll()).array()) {
        const QJsonObject object = value.toObject();
        Transcription entry;
        entry.id = object.value("id").toString();
        entry.text = object.value("text").toString();
        entry.date = QDateTime::fromString(object.value("date").toString(), Qt::ISODate);
        entry.duration = object.value("duration").toDouble();
        entry.language = object.value("language").toString();
        entry.sourceFile = object.value("sourceFile").toString();
        if (!entry.id.isEmpty())
            m_entries.append(entry);
    }
}

bool History::save() {
    QDir().mkpath(QFileInfo(m_path).absolutePath());
    QJsonArray array;
    for (const auto &entry : m_entries)
        array.append(toJson(entry));
    // QSaveFile writes beside the target and renames, so a crash mid-write
    // can't leave a truncated history.
    QSaveFile file(m_path);
    if (!file.open(QIODevice::WriteOnly))
        return false;
    file.write(QJsonDocument(array).toJson(QJsonDocument::Indented));
    return file.commit();
}

const Transcription *History::find(const QString &id) const {
    for (const auto &entry : m_entries)
        if (entry.id == id)
            return &entry;
    return nullptr;
}

QVariantList History::search(const QString &query) const {
    QVariantList list;
    const QString needle = query.trimmed();
    for (const auto &entry : m_entries) {
        if (!needle.isEmpty() && !entry.text.contains(needle, Qt::CaseInsensitive))
            continue;
        list.append(QVariantMap{
            {"id", entry.id},
            {"text", entry.text},
            {"date", QLocale().toString(entry.date.toLocalTime(), QLocale::ShortFormat)},
            {"duration", formatDuration(entry.duration)},
            {"language", entry.language},
            {"sourceFile", entry.sourceFile}});
    }
    return list;
}

bool History::add(const Transcription &entry) {
    m_entries.prepend(entry);
    const bool saved = save();
    emit changed();
    return saved;
}

bool History::remove(const QString &id) {
    m_entries.removeIf([&id](const Transcription &entry) { return entry.id == id; });
    const bool saved = save();
    emit changed();
    return saved;
}

bool History::clear() {
    m_entries.clear();
    const bool saved = save();
    emit changed();
    return saved;
}

QString History::exportAs(const QString &id, const QString &format) const {
    const Transcription *entry = find(id);
    if (!entry)
        return {};
    if (format == "markdown") {
        QString out = "# Transcription\n\n";
        out += "**Date:** " + QLocale().toString(entry->date.toLocalTime(), QLocale::ShortFormat) + "\n";
        out += "**Duration:** " + formatDuration(entry->duration) + "\n";
        out += "**Language:** " + entry->language + "\n";
        if (!entry->sourceFile.isEmpty())
            out += "**Source:** " + entry->sourceFile + "\n";
        return out + "\n---\n\n" + entry->text + "\n";
    }
    if (format == "json")
        return QString::fromUtf8(QJsonDocument(toJson(*entry)).toJson(QJsonDocument::Indented));
    if (format == "srt") {
        // One cue spanning the whole recording; the engines give no timings.
        const int total = std::max(1, int(entry->duration));
        return QString("1\n00:00:00,000 --> %1:%2:%3,000\n%4\n")
            .arg(total / 3600, 2, 10, QChar('0'))
            .arg(total / 60 % 60, 2, 10, QChar('0'))
            .arg(total % 60, 2, 10, QChar('0'))
            .arg(entry->text);
    }
    return entry->text + "\n";
}
