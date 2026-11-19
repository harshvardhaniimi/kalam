#pragma once

#include <QNetworkAccessManager>
#include <QObject>
#include <QVariantList>

class QFile;
class QNetworkReply;

// The Whisper models Kalam offers, as whisper.cpp ggml files downloaded
// from Hugging Face into ~/.local/share/kalam/models.
class Models : public QObject {
    Q_OBJECT

public:
    struct Model {
        QString id;
        QString name;
        QString file;
        QString size;
        const char *description;
    };

    explicit Models(const QString &directory = {}, QObject *parent = nullptr);
    ~Models() override;

    static const QList<Model> &catalog();
    static bool isKnown(const QString &id);

    QString directory() const { return m_directory; }
    QString path(const QString &id) const;
    bool isInstalled(const QString &id) const;

    // The catalog with each model's install and download state, for QML.
    QVariantList list() const;

    QString downloading() const { return m_downloading; }
    double progress() const { return m_progress; }
    void download(const QString &id);
    void cancel();
    bool remove(const QString &id);

signals:
    void changed();
    void downloadFinished(const QString &id);
    void downloadFailed(const QString &id, const QString &message);

private:
    void finish(const QString &error);

    QString m_directory;
    QNetworkAccessManager m_network;
    QNetworkReply *m_reply = nullptr;
    QFile *m_part = nullptr;
    QString m_downloading;
    double m_progress = 0;
};
