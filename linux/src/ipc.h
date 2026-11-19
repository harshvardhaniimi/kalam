#pragma once

#include <QJsonObject>
#include <QLocalServer>
#include <QObject>
#include <functional>

// One Kalam runs per session. Command-line invocations (and through them
// Omarchy's dictation keys) reach it over a local socket: one JSON object
// per line each way.
namespace Ipc {

QString socketPath();

// Sends a command to the running instance. False when none is running.
bool send(const QJsonObject &command, QJsonObject *reply, int timeoutMs);

class Server : public QObject {
    Q_OBJECT

public:
    // The handler answers through `respond`, at once or later (a file
    // transcription replies when it finishes).
    using Respond = std::function<void(const QJsonObject &)>;
    using Handler = std::function<void(const QJsonObject &command, Respond respond)>;

    explicit Server(Handler handler, QObject *parent = nullptr);
    bool listen();

private:
    Handler m_handler;
    QLocalServer m_server;
};

}
