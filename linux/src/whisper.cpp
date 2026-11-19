#include "whisper.h"

#include <QHttpMultiPart>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTcpServer>
#include <QTcpSocket>
#include <QThread>

#include <csignal>
#include <sys/prctl.h>

#include "audio.h"

Whisper::Whisper(QObject *parent) : QObject(parent) {
    m_server.setProcessChannelMode(QProcess::MergedChannels);
    // The server must not outlive Kalam, even when Kalam is killed.
    m_server.setChildProcessModifier([] { prctl(PR_SET_PDEATHSIG, SIGTERM); });
    // Loading a large model takes seconds; poll until the port answers.
    m_probe.setInterval(150);
    connect(&m_probe, &QTimer::timeout, this, &Whisper::probe);
    connect(&m_server, &QProcess::finished, this, [this] {
        if (m_model.isEmpty())
            return;
        // A GPU driver that can't run the model takes the server down while
        // loading; try once more on the CPU before giving up.
        if (!m_ready && m_gpu) {
            start(false);
            return;
        }
        m_model.clear();
        m_ready = false;
        fail(tr("The local Whisper engine stopped unexpectedly."));
    });
    connect(&m_server, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            m_model.clear();
            fail(tr("whisper-server is not installed. Install the whisper-cpp package."));
        }
    });
}

Whisper::~Whisper() {
    unload();
}

bool Whisper::available() {
    return !QStandardPaths::findExecutable("whisper-server").isEmpty();
}

void Whisper::unload() {
    m_model.clear();
    m_ready = false;
    m_probe.stop();
    if (m_server.state() != QProcess::NotRunning) {
        m_server.terminate();
        if (!m_server.waitForFinished(2000)) {
            m_server.kill();
            m_server.waitForFinished(1000);
        }
    }
}

void Whisper::load(const QString &modelPath) {
    if (modelPath == m_model && m_server.state() != QProcess::NotRunning)
        return;
    unload();
    m_model = modelPath;
    start(true);
}

void Whisper::start(bool gpu) {
    m_gpu = gpu;
    m_ready = false;
    m_probes = 0;

    // Ask the kernel for a free port, then hand it to the server.
    QTcpServer picker;
    picker.listen(QHostAddress::LocalHost, 0);
    m_port = picker.serverPort();
    picker.close();

    QStringList arguments{"-m", m_model, "--host", "127.0.0.1", "--port", QString::number(m_port),
                          "-t", QString::number(std::clamp(QThread::idealThreadCount() / 2, 2, 8))};
    if (!gpu)
        arguments << "--no-gpu";
    m_server.start("whisper-server", arguments);
    m_probe.start();
}

void Whisper::probe() {
    if (m_server.state() == QProcess::NotRunning) {
        m_probe.stop();
        return;
    }
    // Two minutes covers a cold large model on a slow disk.
    if (++m_probes > 800) {
        m_probe.stop();
        unload();
        fail(tr("The local Whisper model took too long to load."));
        return;
    }
    QTcpSocket socket;
    socket.connectToHost(QHostAddress::LocalHost, m_port);
    if (!socket.waitForConnected(50))
        return;
    m_probe.stop();
    m_ready = true;
    const QList<Job> waiting = m_waiting;
    m_waiting.clear();
    for (const auto &job : waiting)
        send(job);
}

void Whisper::fail(const QString &message) {
    const QList<Job> waiting = m_waiting;
    m_waiting.clear();
    for (const auto &job : waiting)
        job.done({}, message);
}

QString Whisper::clean(const QString &text) {
    static const QRegularExpression markers(R"(\[[^\]]*\]|\([^)]*(music|silence|applause|noise)[^)]*\))",
                                            QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression spaces(R"(\s+)");
    QString cleaned = text;
    cleaned.remove(markers);
    return cleaned.replace(spaces, " ").trimmed();
}

void Whisper::transcribe(const QVector<float> &samples, const QString &modelPath, const QString &language,
                         const QString &prompt, Callback done) {
    if (!available()) {
        done({}, tr("whisper-server is not installed. Install the whisper-cpp package."));
        return;
    }
    const Job job{samples, language, prompt, std::move(done)};
    load(modelPath);
    if (m_ready)
        send(job);
    else
        m_waiting.append(job);
}

void Whisper::send(const Job &job) {
    auto *form = new QHttpMultiPart(QHttpMultiPart::FormDataType);
    auto field = [form](const QString &name, const QByteArray &value) {
        QHttpPart part;
        part.setHeader(QNetworkRequest::ContentDispositionHeader, QString("form-data; name=\"%1\"").arg(name));
        part.setBody(value);
        form->append(part);
    };
    field("response_format", "json");
    field("temperature", "0.0");
    field("language", job.language.isEmpty() ? "auto" : job.language.toUtf8());
    if (!job.prompt.isEmpty())
        field("prompt", job.prompt.toUtf8());

    QHttpPart file;
    file.setHeader(QNetworkRequest::ContentDispositionHeader, "form-data; name=\"file\"; filename=\"audio.wav\"");
    file.setHeader(QNetworkRequest::ContentTypeHeader, "audio/wav");
    file.setBody(Audio::makeWav(job.samples));
    form->append(file);

    QNetworkRequest request(QUrl(QString("http://127.0.0.1:%1/inference").arg(m_port)));
    // A ten-minute recording on a CPU-only machine can take a while.
    request.setTransferTimeout(15 * 60 * 1000);
    QNetworkReply *reply = m_network.post(request, form);
    form->setParent(reply);
    connect(reply, &QNetworkReply::finished, this, [this, reply, done = job.done] {
        reply->deleteLater();
        const QByteArray body = reply->readAll();
        if (reply->error() != QNetworkReply::NoError) {
            done({}, tr("Local transcription failed: %1").arg(reply->errorString()));
            return;
        }
        const QJsonObject object = QJsonDocument::fromJson(body).object();
        if (object.contains("error")) {
            done({}, tr("Local transcription failed: %1").arg(object.value("error").toString()));
            return;
        }
        const QString text = clean(object.value("text").toString());
        if (text.isEmpty())
            done({}, tr("No speech was detected."));
        else
            done(text, {});
    });
}
