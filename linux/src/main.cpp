// kalam — speech-to-text dictation for Hindi + English, private by default.

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QIcon>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QTextStream>
#include <QThread>
#include <QTimer>
#include <QUrl>

#include "backend.h"
#include "indicator.h"
#include "ipc.h"
#include "theme.h"
#include "translator.h"

namespace {
const char *version = "0.1.0";

const char *usage =
    "Usage: kalam [command] [--json]\n"
    "\n"
    "  open [file]        Show the window (the default), transcribing a file if given\n"
    "  daemon             Run in the background without a window\n"
    "  start              Start dictating\n"
    "  stop               Stop dictating and paste the transcript at the cursor\n"
    "  toggle             Start or stop dictating\n"
    "  cancel             Throw the current recording away\n"
    "  transcribe <file>  Print the transcript of an audio or video file\n"
    "  status             Show whether Kalam is running and what it is doing\n"
    "  quit               Stop the background process\n";

void setUpApplication(QGuiApplication &app) {
    app.setApplicationName("kalam");
    app.setApplicationVersion(version);
    // Matches the window to kalam.desktop, so the compositor (Wayland
    // app_id) and the launcher pick up the installed icon.
    app.setDesktopFileName("kalam");
    app.setWindowIcon(QIcon::fromTheme("kalam"));
}

// A one-shot `kalam transcribe` when nothing is running: no display, no
// notifications, just the transcript.
int transcribeOnce(int argc, char *argv[], const QString &path, bool json) {
    qputenv("QT_QPA_PLATFORM", "offscreen");
    QGuiApplication app(argc, argv);
    setUpApplication(app);
    Backend::Options options;
    options.oneShot = true;
    Backend backend(options);
    int code = 0;
    QTimer::singleShot(0, &app, [&] {
        backend.transcribeFile(path, Backend::Delivery::CommandLine, [&](const QString &text, const QString &error) {
            QTextStream out(stdout), err(stderr);
            if (json)
                out << QJsonDocument(QJsonObject{{"ok", error.isEmpty()}, {"text", text}, {"error", error}})
                           .toJson(QJsonDocument::Compact) << "\n";
            else if (error.isEmpty())
                out << text << "\n";
            if (!error.isEmpty()) {
                err << error << "\n";
                code = 1;
            }
            app.quit();
        });
    });
    app.exec();
    return code;
}

int runInstance(int argc, char *argv[], bool showWindow, const QString &file) {
    QGuiApplication app(argc, argv);
    setUpApplication(app);
    // Kalam keeps listening for the dictation keys after its window closes.
    app.setQuitOnLastWindowClosed(false);
    QQuickStyle::setStyle("Material");

    // Installed before anything is translated, and every qsTr() binding is
    // re-evaluated when the Omarchy language changes.
    Translator translator;
    app.installTranslator(&translator);

    Theme theme;
    Backend backend;

    QQmlApplicationEngine engine;
    QObject::connect(&translator, &Translator::changed, &engine, &QQmlEngine::retranslate);
    engine.rootContext()->setContextProperty("translator", &translator);
    engine.rootContext()->setContextProperty("theme", &theme);
    engine.rootContext()->setContextProperty("backend", &backend);

    Indicator indicator(&engine);
    QObject::connect(&backend, &Backend::stateChanged, &indicator,
                     [&] { indicator.setVisible(backend.indicatorVisible()); });

    // The Omarchy bar widget mirrors this file; it is gone when Kalam is.
    const QString stateFile = QFileInfo(Ipc::socketPath()).absolutePath() + "/kalam.state";
    auto writeState = [&] {
        QFile file(stateFile);
        if (file.open(QIODevice::WriteOnly | QIODevice::Truncate))
            file.write(backend.state().toUtf8() + "\n");
    };
    QObject::connect(&backend, &Backend::stateChanged, &app, writeState);
    QObject::connect(&app, &QCoreApplication::aboutToQuit, &app, [&] { QFile::remove(stateFile); });

    // The window is built the first time it is asked for; a background
    // start never pays for it.
    QQuickWindow *window = nullptr;
    auto open = [&] {
        if (!window) {
            engine.load(QUrl("qrc:/Main.qml"));
            window = engine.rootObjects().isEmpty() ? nullptr : qobject_cast<QQuickWindow *>(engine.rootObjects().first());
            if (!window)
                return false;
        }
        window->show();
        window->raise();
        window->requestActivate();
        return true;
    };

    Ipc::Server server([&](const QJsonObject &command, Ipc::Server::Respond respond) {
        const QString name = command.value("cmd").toString();
        const QString path = command.value("path").toString();
        QJsonObject reply{{"ok", true}};
        if (name == "open") {
            reply["ok"] = open();
            if (!path.isEmpty())
                backend.transcribeFile(path, Backend::Delivery::Clipboard);
        } else if (name == "start") {
            backend.dictationStart();
        } else if (name == "stop") {
            backend.dictationStop();
        } else if (name == "toggle") {
            backend.dictationToggle();
        } else if (name == "cancel") {
            backend.cancelRecording();
        } else if (name == "transcribe") {
            backend.transcribeFile(path, Backend::Delivery::CommandLine,
                                   [respond](const QString &text, const QString &error) {
                                       respond({{"ok", error.isEmpty()}, {"text", text}, {"error", error}});
                                   });
            return;
        } else if (name == "quit") {
            QTimer::singleShot(0, &app, &QCoreApplication::quit);
        } else if (name != "status" && name != "daemon") {
            reply = {{"ok", false}, {"error", "Unknown command: " + name}};
        }
        if (reply.value("ok").toBool()) {
            reply["running"] = true;
            reply["state"] = backend.state();
            reply["engine"] = backend.engine();
            reply["model"] = backend.model();
            reply["ready"] = backend.canTranscribe();
            // start and toggle report why nothing is recording.
            if ((name == "start" || name == "toggle") && !backend.lastError().isEmpty() && !backend.recording()
                && !backend.processing()) {
                reply["ok"] = false;
                reply["error"] = backend.lastError();
            }
        }
        respond(reply);
    });
    if (!server.listen()) {
        QTextStream(stderr) << "Kalam could not open its socket at " << Ipc::socketPath() << "\n";
        return 1;
    }

    writeState();
    backend.prepare();
    if (showWindow && !open())
        return 1;
    if (!file.isEmpty())
        backend.transcribeFile(file, Backend::Delivery::Clipboard);

    return app.exec();
}
}

int main(int argc, char *argv[]) {
    QStringList arguments;
    for (int i = 1; i < argc; ++i)
        arguments << QString::fromLocal8Bit(argv[i]);
    const bool json = arguments.removeAll("--json") > 0;
    QTextStream out(stdout), err(stderr);

    QString command = arguments.isEmpty() ? "open" : arguments.takeFirst();
    if (command == "-h" || command == "--help" || command == "help") {
        out << usage;
        return 0;
    }
    if (command == "-v" || command == "--version") {
        out << "kalam " << version << "\n";
        return 0;
    }
    // The launcher runs `kalam %f`, so a bare path opens the window on it.
    if (QFileInfo(command).isFile()) {
        arguments.prepend(command);
        command = "open";
    }
    static const QStringList commands{"open", "daemon", "start", "stop", "toggle", "cancel", "transcribe", "status", "quit"};
    if (!commands.contains(command)) {
        err << "Unknown command: " << command << "\n\n" << usage;
        return 1;
    }

    QString path = arguments.isEmpty() ? QString() : QFileInfo(arguments.first()).absoluteFilePath();
    if (command == "transcribe" && path.isEmpty()) {
        err << "Usage: kalam transcribe <file> [--json]\n";
        return 1;
    }
    if (!path.isEmpty() && !QFileInfo(path).isFile()) {
        err << path << " is not a file.\n";
        return 1;
    }

    const QJsonObject request{{"cmd", command}, {"path", path}};
    // A long file on a slow machine can take many minutes to transcribe.
    const int timeout = command == "transcribe" ? 60 * 60 * 1000 : 10 * 1000;
    auto report = [&](const QJsonObject &reply) {
        if (json)
            out << QJsonDocument(reply).toJson(QJsonDocument::Compact) << "\n";
        else if (command == "transcribe" && reply.value("ok").toBool())
            out << reply.value("text").toString() << "\n";
        else if (command == "status")
            out << reply.value("state").toString() << " (" << reply.value("engine").toString() << ", "
                << reply.value("model").toString() << (reply.value("ready").toBool() ? "" : ", not ready") << ")\n";
        if (!reply.value("ok").toBool()) {
            const QString error = reply.value("error").toString();
            err << (error.isEmpty() ? "Kalam did not answer." : error) << "\n";
            return 1;
        }
        return 0;
    };

    QJsonObject reply;
    if (Ipc::send(request, &reply, timeout)) {
        if (command == "daemon" && !json)
            out << "Kalam is already running.\n";
        return report(reply);
    }

    // Nothing is running.
    if (command == "stop" || command == "cancel" || command == "quit")
        return 0;
    if (command == "status") {
        if (json)
            out << "{\"ok\":true,\"running\":false}\n";
        else
            out << "not running\n";
        return 0;
    }
    if (command == "transcribe")
        return transcribeOnce(argc, argv, path, json);
    if (command == "start" || command == "toggle") {
        // The dictation keys work even before the service is enabled: start
        // the background process, then pass the command on.
        if (!QProcess::startDetached(QFileInfo("/proc/self/exe").canonicalFilePath(), {"daemon"})) {
            err << "Kalam could not start its background process.\n";
            return 1;
        }
        for (int attempt = 0; attempt < 100; ++attempt) {
            QThread::msleep(100);
            if (Ipc::send(request, &reply, timeout))
                return report(reply);
        }
        err << "Kalam did not start in time.\n";
        return 1;
    }
    return runInstance(argc, argv, command == "open", path);
}
