#pragma once

#include <QDateTime>
#include <QList>
#include <QObject>
#include <QVariantList>

struct Transcription {
    QString id;
    QString text;
    QDateTime date;
    double duration = 0;
    QString language;
    QString sourceFile;
};

// Every transcript, newest first, kept as one JSON file that is replaced
// atomically on each change. The layout matches the macOS app's history.
class History : public QObject {
    Q_OBJECT

public:
    explicit History(const QString &path = {}, QObject *parent = nullptr);

    const QList<Transcription> &entries() const { return m_entries; }
    QVariantList search(const QString &query) const;

    // False when the file could not be written; the entry stays in memory.
    bool add(const Transcription &entry);
    bool remove(const QString &id);
    bool clear();

    // "text", "markdown", "json", or "srt".
    QString exportAs(const QString &id, const QString &format) const;

    static QString formatDuration(double seconds);

signals:
    void changed();

private:
    void load();
    bool save();
    const Transcription *find(const QString &id) const;

    QString m_path;
    QList<Transcription> m_entries;
};
