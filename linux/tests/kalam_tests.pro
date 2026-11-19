QT += core gui qml quick quickcontrols2 testlib dbus multimedia network
CONFIG += c++17 testcase
TARGET = kalam_tests
TEMPLATE = app

INCLUDEPATH += ../src

HEADERS += \
    ../src/audio.h ../src/backend.h ../src/dictionary.h ../src/filepicker.h ../src/history.h \
    ../src/inserter.h ../src/models.h ../src/notifier.h ../src/portalfilepicker.h ../src/recorder.h \
    ../src/sarvam.h ../src/secretstore.h ../src/theme.h ../src/translator.h ../src/whisper.h
SOURCES += kalam_tests.cpp \
    ../src/audio.cpp ../src/backend.cpp ../src/dictionary.cpp ../src/history.cpp \
    ../src/inserter.cpp ../src/models.cpp ../src/notifier.cpp ../src/portalfilepicker.cpp ../src/recorder.cpp \
    ../src/sarvam.cpp ../src/secretstore.cpp ../src/theme.cpp ../src/translator.cpp ../src/whisper.cpp
