#pragma once

#include <QAudioFormat>
#include <QElapsedTimer>
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVector>

class QAudioSource;
class QIODevice;
class QMediaDevices;

// Captures the microphone into memory. Samples are appended as they arrive
// and at the rate the device really delivers, then resampled to 16 kHz once
// at stop, so the tail of a recording is never lost to a conversion queue.
class Recorder : public QObject {
    Q_OBJECT

public:
    enum class AutoStop { Silence, MaxDuration, DeviceLost };

    // A level below this counts as silence.
    static constexpr float silenceLevel = 0.08f;
    // Forgotten recordings end themselves after this much silence...
    static constexpr int silenceTimeoutSeconds = 120;
    // ...or at this length regardless.
    static constexpr int maxDurationSeconds = 600;

    explicit Recorder(QObject *parent = nullptr);
    ~Recorder() override;

    bool isRecording() const { return m_source != nullptr; }
    float level() const { return m_level; }
    double duration() const { return m_duration; }

    // Device ids and names for the settings page; "" is the system default.
    QVariantList devices() const;

    // Empty on success, otherwise what went wrong, in the user's words.
    QString start(const QString &deviceId);
    // Ends the recording and hands back 16 kHz mono samples (empty when the
    // microphone delivered nothing).
    QVector<float> stop();

signals:
    void levelChanged();
    void durationChanged();
    void devicesChanged();
    void autoStopped(Recorder::AutoStop reason);

private:
    void readAvailable();
    void tick();

    QMediaDevices *m_devices;
    QAudioSource *m_source = nullptr;
    QIODevice *m_io = nullptr;
    QAudioFormat m_format;
    QVector<float> m_samples;
    QTimer m_ticker;
    QElapsedTimer m_clock, m_sinceVoice;
    float m_level = 0;
    double m_duration = 0;
};
