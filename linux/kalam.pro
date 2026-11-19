QT += core gui qml quick quickcontrols2 dbus multimedia network

CONFIG += c++17 release
TARGET = kalam
TEMPLATE = app

# The recording pill is a layer-shell surface, so it floats over every
# workspace without taking focus from the window being dictated into.
LIBS += -lLayerShellQtInterface

HEADERS += \
    src/audio.h \
    src/backend.h \
    src/dictionary.h \
    src/filepicker.h \
    src/history.h \
    src/indicator.h \
    src/inserter.h \
    src/ipc.h \
    src/models.h \
    src/notifier.h \
    src/portalfilepicker.h \
    src/recorder.h \
    src/sarvam.h \
    src/secretstore.h \
    src/theme.h \
    src/translator.h \
    src/whisper.h

SOURCES += \
    src/main.cpp \
    src/audio.cpp \
    src/backend.cpp \
    src/dictionary.cpp \
    src/history.cpp \
    src/indicator.cpp \
    src/inserter.cpp \
    src/ipc.cpp \
    src/models.cpp \
    src/notifier.cpp \
    src/portalfilepicker.cpp \
    src/recorder.cpp \
    src/sarvam.cpp \
    src/secretstore.cpp \
    src/theme.cpp \
    src/translator.cpp \
    src/whisper.cpp

RESOURCES += src/resources.qrc
