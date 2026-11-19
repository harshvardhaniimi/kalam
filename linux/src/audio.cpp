#include "audio.h"

#include <QtEndian>
#include <algorithm>
#include <cmath>
#include <cstring>

namespace Audio {

QByteArray makeWav(const QVector<float> &samples, int rate) {
    const quint32 dataSize = quint32(samples.size()) * 2;
    QByteArray wav;
    wav.reserve(44 + int(dataSize));
    auto put32 = [&wav](quint32 v) { v = qToLittleEndian(v); wav.append(reinterpret_cast<const char *>(&v), 4); };
    auto put16 = [&wav](quint16 v) { v = qToLittleEndian(v); wav.append(reinterpret_cast<const char *>(&v), 2); };

    wav.append("RIFF");
    put32(36 + dataSize);
    wav.append("WAVEfmt ");
    put32(16);
    put16(1);                 // PCM
    put16(1);                 // mono
    put32(quint32(rate));
    put32(quint32(rate) * 2); // byte rate
    put16(2);                 // block align
    put16(16);                // bits per sample
    wav.append("data");
    put32(dataSize);
    for (const float sample : samples)
        put16(quint16(qint16(std::clamp(sample, -1.0f, 1.0f) * 32767.0f)));
    return wav;
}

QList<QVector<float>> chunks(const QVector<float> &samples, double seconds, int rate) {
    QList<QVector<float>> pieces;
    const qsizetype size = std::max<qsizetype>(1, qsizetype(seconds * rate));
    for (qsizetype start = 0; start < samples.size(); start += size)
        pieces.append(samples.mid(start, size));
    return pieces;
}

QVector<float> resample(const QVector<float> &samples, int fromRate, int toRate) {
    if (fromRate == toRate || fromRate <= 0 || samples.isEmpty())
        return samples;
    const double step = double(fromRate) / toRate;
    const qsizetype count = qsizetype(samples.size() / step);
    QVector<float> out(count);
    // Averaging the span each output sample covers keeps a downsample from
    // aliasing; an upsample falls back to plain interpolation.
    const int span = std::max(1, int(std::floor(step)));
    for (qsizetype i = 0; i < count; ++i) {
        const double position = i * step;
        const qsizetype index = qsizetype(position);
        if (span > 1) {
            float sum = 0;
            int used = 0;
            for (int k = 0; k < span && index + k < samples.size(); ++k, ++used)
                sum += samples[index + k];
            out[i] = used ? sum / used : 0;
        } else {
            const float a = samples[index];
            const float b = index + 1 < samples.size() ? samples[index + 1] : a;
            out[i] = a + (b - a) * float(position - index);
        }
    }
    return out;
}

float level(const float *samples, qsizetype count) {
    if (count <= 0)
        return 0;
    double sum = 0;
    for (qsizetype i = 0; i < count; ++i)
        sum += double(samples[i]) * samples[i];
    const double rms = std::sqrt(sum / count);
    const double power = 20 * std::log10(std::max(rms, 1e-12));
    return float(std::clamp((power + 50) / 50, 0.0, 1.0));
}

QVector<float> fromFloat32(const QByteArray &bytes) {
    QVector<float> samples(bytes.size() / 4);
    if (!samples.isEmpty())
        std::memcpy(samples.data(), bytes.constData(), size_t(samples.size()) * 4);
    return samples;
}

}
