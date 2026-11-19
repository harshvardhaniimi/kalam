#pragma once

#include <QNetworkAccessManager>
#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QVector>
#include <functional>

// Local transcription. whisper.cpp's whisper-server runs as a child process
// with the chosen model loaded, bound to localhost, so each dictation costs
// only the inference and not a model load. Nothing leaves the machine.
class Whisper : public QObject {
    Q_OBJECT

public:
    // Called with the transcript, or with an empty transcript and an error.
    using Callback = std::function<void(const QString &text, const QString &error)>;

    explicit Whisper(QObject *parent = nullptr);
    ~Whisper() override;

    static bool available();

    // Starts (or restarts) the server on this model so the first dictation
    // is fast. Safe to call again with the same model.
    void load(const QString &modelPath);
    void unload();

    // `language` is a Whisper code or "auto"; `prompt` biases spelling
    // toward the user's dictionary words.
    void transcribe(const QVector<float> &samples, const QString &modelPath, const QString &language,
                    const QString &prompt, Callback done);

    // "[BLANK_AUDIO]" and friends are Whisper's markers, not speech.
    static QString clean(const QString &text);

private:
    struct Job {
        QVector<float> samples;
        QString language, prompt;
        Callback done;
    };

    void start(bool gpu);
    void probe();
    void fail(const QString &message);
    void send(const Job &job);

    QProcess m_server;
    QNetworkAccessManager m_network;
    QTimer m_probe;
    QString m_model;
    int m_port = 0;
    int m_probes = 0;
    bool m_ready = false;
    bool m_gpu = true;
    QList<Job> m_waiting;
};
