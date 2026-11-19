#pragma once

#include <QNetworkAccessManager>
#include <QObject>
#include <QUrl>
#include <QVector>
#include <functional>

// Client for Sarvam AI's speech-to-text REST API (Saaras v3), the engine to
// pick for Hindi and Hinglish. The endpoint takes about 30 seconds of audio
// per request, so longer recordings go up in pieces and the transcripts are
// joined.
class Sarvam : public QObject {
    Q_OBJECT

public:
    using Callback = std::function<void(const QString &text, const QString &error)>;

    static constexpr double chunkSeconds = 25.0;

    // Tests point `endpoint` at a local server.
    explicit Sarvam(const QUrl &endpoint = QUrl("https://api.sarvam.ai/speech-to-text"), QObject *parent = nullptr);

    // `mode` is "codemix" (natural Hinglish) or "transcribe" (native script).
    void transcribe(const QVector<float> &samples, const QString &apiKey, const QString &mode, Callback done);

private:
    struct Job {
        QList<QVector<float>> chunks;
        QStringList transcripts;
        QString apiKey, mode;
        Callback done;
    };

    void next(std::shared_ptr<Job> job);

    QUrl m_endpoint;
    QNetworkAccessManager m_network;
};
