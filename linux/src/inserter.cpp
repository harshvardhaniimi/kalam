#include "inserter.h"

#include <QClipboard>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QStandardPaths>
#include <QThread>

bool Inserter::copy(const QString &text) {
    // wl-copy owns the selection from its own process, which works even
    // when Kalam has no focused window (a Wayland client otherwise can't
    // set the clipboard from the background).
    const QString tool = QStandardPaths::findExecutable("wl-copy");
    if (!tool.isEmpty()) {
        QProcess process;
        process.start(tool, {"--type", "text/plain;charset=utf-8"});
        process.write(text.toUtf8());
        process.closeWriteChannel();
        if (process.waitForFinished(3000) && process.exitCode() == 0)
            return true;
    }
    if (auto *clipboard = QGuiApplication::clipboard()) {
        clipboard->setText(text);
        return true;
    }
    return false;
}

QStringList Inserter::pasteArguments(const QStringList &tags) {
    // Terminals paste with Ctrl+Shift+V; Omarchy tags them "terminal"
    // (dynamic tags carry a trailing "*").
    bool terminal = false;
    for (QString tag : tags) {
        if (tag.endsWith('*'))
            tag.chop(1);
        terminal = terminal || tag == "terminal";
    }
    return terminal ? QStringList{"-M", "ctrl", "-M", "shift", "-k", "v", "-m", "shift", "-m", "ctrl"}
                    : QStringList{"-M", "ctrl", "-k", "v", "-m", "ctrl"};
}

Inserter::Result Inserter::insert(const QString &text) {
    if (!copy(text))
        return Result::Failed;

    const QString wtype = QStandardPaths::findExecutable("wtype");
    if (wtype.isEmpty())
        return Result::CopiedOnly;

    QStringList tags;
    const QString hyprctl = QStandardPaths::findExecutable("hyprctl");
    if (!hyprctl.isEmpty()) {
        QProcess process;
        process.start(hyprctl, {"-j", "activewindow"});
        if (process.waitForFinished(1000)) {
            const QJsonObject window = QJsonDocument::fromJson(process.readAllStandardOutput()).object();
            // Pasting into Kalam's own window would only confuse it.
            if (window.value("class").toString() == "kalam")
                return Result::CopiedOnly;
            for (const auto &tag : window.value("tags").toArray())
                tags.append(tag.toString());
        }
    }

    // Give the compositor a moment to hand the selection to wl-copy.
    QThread::msleep(60);
    QProcess paste;
    paste.start(wtype, pasteArguments(tags));
    return paste.waitForFinished(2000) && paste.exitCode() == 0 ? Result::Pasted : Result::CopiedOnly;
}
