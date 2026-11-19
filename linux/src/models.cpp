#include "models.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QNetworkReply>
#include <QStandardPaths>
#include <QVariantMap>

const QList<Models::Model> &Models::catalog() {
    static const QList<Model> models{
        {"tiny", "Tiny", "ggml-tiny.bin", "75 MB", QT_TRANSLATE_NOOP("Models", "Fast, English only in practice")},
        {"base", "Base", "ggml-base.bin", "142 MB", QT_TRANSLATE_NOOP("Models", "Balanced for English; poor for Hindi")},
        {"small", "Small", "ggml-small.bin", "466 MB", QT_TRANSLATE_NOOP("Models", "Better accuracy; still weak for Hindi")},
        {"medium", "Medium", "ggml-medium.bin", "1.5 GB", QT_TRANSLATE_NOOP("Models", "High accuracy")},
        {"turbo", "Large Turbo", "ggml-large-v3-turbo.bin", "1.6 GB",
         QT_TRANSLATE_NOOP("Models", "Best multilingual (Hindi + English) - recommended")},
        {"large", "Large", "ggml-large-v3.bin", "3.1 GB", QT_TRANSLATE_NOOP("Models", "Best accuracy (large-v3), slowest")},
    };
    return models;
}

bool Models::isKnown(const QString &id) {
    for (const auto &model : catalog())
        if (model.id == id)
            return true;
    return false;
}

Models::Models(const QString &directory, QObject *parent)
    : QObject(parent),
      m_directory(directory.isEmpty()
                      ? QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/kalam/models"
                      : directory) {}

Models::~Models() {
    cancel();
}

QString Models::path(const QString &id) const {
    for (const auto &model : catalog())
        if (model.id == id)
            return m_directory + "/" + model.file;
    return {};
}

bool Models::isInstalled(const QString &id) const {
    const QString file = path(id);
    return !file.isEmpty() && QFileInfo(file).size() > 1024 * 1024;
}

QVariantList Models::list() const {
    QVariantList list;
    for (const auto &model : catalog())
        list.append(QVariantMap{
            {"id", model.id},
            {"name", model.name},
            {"size", model.size},
            {"description", QCoreApplication::translate("Models", model.description)},
            {"installed", isInstalled(model.id)},
            {"downloading", m_downloading == model.id},
            {"progress", m_downloading == model.id ? m_progress : 0.0}});
    return list;
}

void Models::download(const QString &id) {
    if (!m_downloading.isEmpty() || !isKnown(id) || isInstalled(id))
        return;
    QDir().mkpath(m_directory);

    // Download beside the target and rename when complete, so a half
    // downloaded model is never mistaken for an installed one.
    m_part = new QFile(path(id) + ".part", this);
    if (!m_part->open(QIODevice::WriteOnly)) {
        delete m_part;
        m_part = nullptr;
        emit downloadFailed(id, tr("Could not write to %1.").arg(m_directory));
        return;
    }

    m_downloading = id;
    m_progress = 0;
    QNetworkRequest request(
        QUrl("https://huggingface.co/ggerganov/whisper.cpp/resolve/main/" + QFileInfo(path(id)).fileName()));
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    m_reply = m_network.get(request);
    connect(m_reply, &QNetworkReply::readyRead, this, [this] {
        if (m_part && m_reply)
            m_part->write(m_reply->readAll());
    });
    connect(m_reply, &QNetworkReply::downloadProgress, this, [this](qint64 received, qint64 total) {
        const double progress = total > 0 ? double(received) / total : 0;
        // Whole percents are plenty for a progress bar.
        if (int(progress * 100) != int(m_progress * 100)) {
            m_progress = progress;
            emit changed();
        }
    });
    connect(m_reply, &QNetworkReply::finished, this, [this] {
        const bool ok = m_reply->error() == QNetworkReply::NoError;
        finish(ok ? QString() : m_reply->errorString());
    });
    emit changed();
}

void Models::finish(const QString &error) {
    const QString id = m_downloading;
    const QString target = path(id);
    QString problem = error;

    if (m_part) {
        if (m_reply)
            m_part->write(m_reply->readAll());
        m_part->close();
        // A captive portal or error page is small; a model never is.
        if (problem.isEmpty() && m_part->size() < 1024 * 1024)
            problem = tr("The download was incomplete.");
        if (problem.isEmpty()) {
            QFile::remove(target);
            if (!m_part->rename(target))
                problem = tr("Could not write to %1.").arg(m_directory);
        }
        if (!problem.isEmpty())
            m_part->remove();
        m_part->deleteLater();
        m_part = nullptr;
    }
    if (m_reply) {
        m_reply->deleteLater();
        m_reply = nullptr;
    }
    m_downloading.clear();
    m_progress = 0;
    emit changed();
    if (id.isEmpty())
        return;
    if (problem.isEmpty())
        emit downloadFinished(id);
    else if (problem != "cancelled")
        emit downloadFailed(id, problem);
}

void Models::cancel() {
    if (m_downloading.isEmpty() || !m_reply)
        return;
    // abort() emits finished; drop that connection and tidy up here.
    m_reply->disconnect(this);
    m_reply->abort();
    finish("cancelled");
}

bool Models::remove(const QString &id) {
    const QString file = path(id);
    const bool removed = !file.isEmpty() && QFile::remove(file);
    emit changed();
    return removed;
}
