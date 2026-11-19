#include "recorder.h"

#include <QAudioDevice>
#include <QAudioSource>
#include <QMediaDevices>
#include <QVariantMap>

#include "audio.h"

Recorder::Recorder(QObject *parent) : QObject(parent), m_devices(new QMediaDevices(this)) {
    connect(m_devices, &QMediaDevices::audioInputsChanged, this, &Recorder::devicesChanged);
    m_ticker.setInterval(100);
    connect(&m_ticker, &QTimer::timeout, this, &Recorder::tick);
}

Recorder::~Recorder() {
    if (m_source)
        stop();
}

QVariantList Recorder::devices() const {
    QVariantList list;
    for (const auto &device : QMediaDevices::audioInputs())
        list.append(QVariantMap{{"id", QString::fromUtf8(device.id())}, {"name", device.description()}});
    return list;
}

QString Recorder::start(const QString &deviceId) {
    if (m_source)
        return {};

    QAudioDevice device = QMediaDevices::defaultAudioInput();
    for (const auto &candidate : QMediaDevices::audioInputs())
        if (!deviceId.isEmpty() && QString::fromUtf8(candidate.id()) == deviceId)
            device = candidate;
    if (device.isNull())
        return tr("No microphone found. Plug one in or pick one in Settings.");

    // Ask for what the engines want; a device that can't do it records in
    // its own format and is converted at stop.
    QAudioFormat format;
    format.setSampleRate(Audio::sampleRate);
    format.setChannelCount(1);
    format.setSampleFormat(QAudioFormat::Float);
    if (!device.isFormatSupported(format))
        format = device.preferredFormat();
    if (format.sampleFormat() != QAudioFormat::Float && format.sampleFormat() != QAudioFormat::Int16
        && format.sampleFormat() != QAudioFormat::Int32)
        format.setSampleFormat(QAudioFormat::Int16);

    m_format = format;
    m_samples.clear();
    m_samples.reserve(format.sampleRate() * 60);
    m_source = new QAudioSource(device, format, this);
    m_io = m_source->start();
    if (!m_io || m_source->error() != QAudio::NoError) {
        delete m_source;
        m_source = nullptr;
        m_io = nullptr;
        return tr("Could not open the microphone (%1).").arg(device.description());
    }
    connect(m_io, &QIODevice::readyRead, this, &Recorder::readAvailable);
    // A microphone unplugged mid-recording stops the source with an error;
    // end with what was captured instead of recording silence forever.
    connect(m_source, &QAudioSource::stateChanged, this, [this](QAudio::State state) {
        if (m_source && state == QAudio::StoppedState && m_source->error() != QAudio::NoError)
            emit autoStopped(AutoStop::DeviceLost);
    });

    m_clock.start();
    m_sinceVoice.start();
    m_duration = 0;
    m_level = 0;
    m_ticker.start();
    emit durationChanged();
    emit levelChanged();
    return {};
}

void Recorder::readAvailable() {
    if (!m_io)
        return;
    const QByteArray bytes = m_io->readAll();
    const int channels = std::max(1, m_format.channelCount());
    const int width = m_format.bytesPerSample();
    if (width <= 0)
        return;
    const qsizetype frames = bytes.size() / (width * channels);
    const qsizetype before = m_samples.size();
    m_samples.resize(before + frames);

    // Downmix to mono as it arrives; every supported format becomes float.
    const char *data = bytes.constData();
    for (qsizetype frame = 0; frame < frames; ++frame) {
        float sum = 0;
        for (int channel = 0; channel < channels; ++channel) {
            const char *sample = data + (frame * channels + channel) * width;
            switch (m_format.sampleFormat()) {
            case QAudioFormat::Float: sum += *reinterpret_cast<const float *>(sample); break;
            case QAudioFormat::Int32: sum += float(*reinterpret_cast<const qint32 *>(sample) / 2147483648.0); break;
            default:                  sum += *reinterpret_cast<const qint16 *>(sample) / 32768.0f; break;
            }
        }
        m_samples[before + frame] = sum / channels;
    }

    if (frames > 0) {
        m_level = Audio::level(m_samples.constData() + before, frames);
        if (m_level > silenceLevel)
            m_sinceVoice.restart();
        emit levelChanged();
    }
}

void Recorder::tick() {
    if (!m_source)
        return;
    m_duration = m_clock.elapsed() / 1000.0;
    emit durationChanged();
    if (m_duration >= maxDurationSeconds)
        emit autoStopped(AutoStop::MaxDuration);
    else if (m_sinceVoice.elapsed() >= silenceTimeoutSeconds * 1000)
        emit autoStopped(AutoStop::Silence);
}

QVector<float> Recorder::stop() {
    if (!m_source)
        return {};
    m_ticker.stop();
    readAvailable();
    m_source->stop();
    // Stopping flushes what the device still held.
    readAvailable();
    m_duration = m_clock.elapsed() / 1000.0;
    m_source->deleteLater();
    m_source = nullptr;
    m_io = nullptr;
    m_level = 0;
    emit levelChanged();
    emit durationChanged();

    QVector<float> samples = Audio::resample(m_samples, m_format.sampleRate());
    m_samples.clear();
    return samples;
}
