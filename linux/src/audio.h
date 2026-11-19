#pragma once

#include <QByteArray>
#include <QList>
#include <QVector>

// Everything downstream of the microphone works on 16 kHz mono float
// samples, the format both Whisper and Sarvam expect.
namespace Audio {

constexpr int sampleRate = 16000;

// A 16-bit PCM mono WAV file holding the samples.
QByteArray makeWav(const QVector<float> &samples, int rate = sampleRate);

// Consecutive pieces of at most `seconds` each, for APIs that cap a request.
QList<QVector<float>> chunks(const QVector<float> &samples, double seconds, int rate = sampleRate);

// Linear resampling to 16 kHz. The input rate is whatever the device gave
// us; it is never assumed.
QVector<float> resample(const QVector<float> &samples, int fromRate, int toRate = sampleRate);

// A buffer's loudness on the 0-1 scale the level meter and the silence
// timeout share: -50 dB and below is 0, full scale is 1.
float level(const float *samples, qsizetype count);

// Little-endian 32-bit float PCM, as ffmpeg's f32le writes it.
QVector<float> fromFloat32(const QByteArray &bytes);

}
