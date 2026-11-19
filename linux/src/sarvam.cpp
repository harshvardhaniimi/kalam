#include "sarvam.h"

#include <QHttpMultiPart>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>

#include "audio.h"

Sarvam::Sarvam(const QUrl &endpoint, QObject *parent) : QObject(parent), m_endpoint(endpoint) {}

void Sarvam::transcribe(const QVector<float> &samples, const QString &apiKey, const QString &mode, Callback done) {
    const QString key = apiKey.trimmed();
    if (key.isEmpty()) {
        done({}, tr("Sarvam API key not set. Add it in Settings, or switch to Local Whisper."));
        return;
    }
    auto job = std::make_shared<Job>();
    job->chunks = Audio::chunks(samples, chunkSeconds);
    job->apiKey = key;
    job->mode = mode;
    job->done = std::move(done);
    next(job);
}

void Sarvam::next(std::shared_ptr<Job> job) {
    if (job->chunks.isEmpty()) {
        const QString text = job->transcripts.join(' ').trimmed();
        if (text.isEmpty())
            job->done({}, tr("Sarvam returned no speech."));
        else
            job->done(text, {});
        return;
    }

    auto *form = new QHttpMultiPart(QHttpMultiPart::FormDataType);
    auto field = [form](const QString &name, const QByteArray &value) {
        QHttpPart part;
        part.setHeader(QNetworkRequest::ContentDispositionHeader, QString("form-data; name=\"%1\"").arg(name));
        part.setBody(value);
        form->append(part);
    };
    field("model", "saaras:v3");
    // Auto-detect Hindi or English per utterance.
    field("language_code", "unknown");
    field("mode", job->mode.toUtf8());

    QHttpPart file;
    file.setHeader(QNetworkRequest::ContentDispositionHeader, "form-data; name=\"file\"; filename=\"audio.wav\"");
    file.setHeader(QNetworkRequest::ContentTypeHeader, "audio/wav");
    file.setBody(Audio::makeWav(job->chunks.takeFirst()));
    form->append(file);

    QNetworkRequest request(m_endpoint);
    request.setRawHeader("api-subscription-key", job->apiKey.toUtf8());
    request.setTransferTimeout(60 * 1000);
    QNetworkReply *reply = m_network.post(request, form);
    form->setParent(reply);
    connect(reply, &QNetworkReply::finished, this, [this, reply, job] {
        reply->deleteLater();
        const QByteArray body = reply->readAll();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (status >= 300) {
            job->done({}, tr("Sarvam API error %1: %2").arg(status).arg(QString::fromUtf8(body.left(200))));
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            job->done({}, tr("Could not reach Sarvam AI: %1").arg(reply->errorString()));
            return;
        }
        const QJsonObject object = QJsonDocument::fromJson(body).object();
        if (!object.value("transcript").isString()) {
            job->done({}, tr("Could not reach Sarvam AI: %1").arg(tr("Unexpected response format")));
            return;
        }
        const QString transcript = object.value("transcript").toString().trimmed();
        if (!transcript.isEmpty())
            job->transcripts.append(transcript);
        next(job);
    });
}
