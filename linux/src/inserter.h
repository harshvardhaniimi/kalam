#pragma once

#include <QObject>

// Puts a transcript on the clipboard and pastes it into the focused window.
class Inserter : public QObject {
    Q_OBJECT

public:
    enum class Result { Pasted, CopiedOnly, Failed };

    explicit Inserter(QObject *parent = nullptr) : QObject(parent) {}

    bool copy(const QString &text);
    // Copies, then sends the paste shortcut the focused window expects.
    // CopiedOnly means the text is on the clipboard but couldn't be pasted
    // (wtype missing, or Kalam's own window has focus).
    Result insert(const QString &text);

    // The chord that pastes into a window with these Hyprland tags and class.
    static QStringList pasteArguments(const QStringList &tags);
};
