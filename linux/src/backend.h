#pragma once

#include <QObject>
#include <QSettings>
#include <QUrl>
#include <QVariantList>
#include <functional>

#include "dictionary.h"
#include "history.h"
#include "inserter.h"
#include "models.h"
#include "notifier.h"
#include "recorder.h"
#include "sarvam.h"
#include "secretstore.h"
#include "whisper.h"

class FilePicker;
class QProcess;

// Kalam's state and the one flow everything goes through: record, stop,
// transcribe with the chosen engine, apply the personal dictionary, then
// deliver the text (paste at the cursor, clipboard, or just the window).
class Backend : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    Q_PROPERTY(bool recording READ recording NOTIFY stateChanged)
    Q_PROPERTY(bool processing READ processing NOTIFY stateChanged)
    Q_PROPERTY(bool indicatorVisible READ indicatorVisible NOTIFY stateChanged)
    Q_PROPERTY(double level READ level NOTIFY levelChanged)
    Q_PROPERTY(QString durationText READ durationText NOTIFY durationChanged)
    Q_PROPERTY(QString transcript READ transcript NOTIFY transcriptChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(bool canTranscribe READ canTranscribe NOTIFY settingsChanged)
    Q_PROPERTY(QString notReadyMessage READ notReadyMessage NOTIFY settingsChanged)
    Q_PROPERTY(bool whisperAvailable READ whisperAvailable CONSTANT)
    Q_PROPERTY(QString engine READ engine WRITE setEngine NOTIFY settingsChanged)
    Q_PROPERTY(QString model READ model WRITE setModel NOTIFY settingsChanged)
    Q_PROPERTY(QString language READ language WRITE setLanguage NOTIFY settingsChanged)
    Q_PROPERTY(QString sarvamMode READ sarvamMode WRITE setSarvamMode NOTIFY settingsChanged)
    Q_PROPERTY(bool hasSarvamKey READ hasSarvamKey NOTIFY settingsChanged)
    Q_PROPERTY(bool keyringAvailable READ keyringAvailable CONSTANT)
    Q_PROPERTY(QString microphone READ microphone WRITE setMicrophone NOTIFY settingsChanged)
    Q_PROPERTY(bool autoPaste READ autoPaste WRITE setAutoPaste NOTIFY settingsChanged)
    Q_PROPERTY(bool sounds READ sounds WRITE setSounds NOTIFY settingsChanged)
    Q_PROPERTY(bool launchAtLogin READ launchAtLogin WRITE setLaunchAtLogin NOTIFY settingsChanged)
    Q_PROPERTY(QVariantList dictionary READ dictionary NOTIFY dictionaryChanged)
    Q_PROPERTY(QVariantList models READ models NOTIFY modelsChanged)
    Q_PROPERTY(QVariantList microphones READ microphones NOTIFY microphonesChanged)
    Q_PROPERTY(QVariantList languages READ languages CONSTANT)
    Q_PROPERTY(int historyRevision READ historyRevision NOTIFY historyChanged)
    Q_PROPERTY(int historyCount READ historyCount NOTIFY historyChanged)

public:
    // Where a finished transcript goes.
    enum class Delivery { Paste, Clipboard, Window, CommandLine };
    using Done = std::function<void(const QString &text, const QString &error)>;

    struct Options {
        // A one-shot command-line run: no notifications, no model warm-up.
        bool oneShot = false;
        // Tests keep everything in a temp directory and off the keyring.
        QString configDirectory, dataDirectory, secretTool;
        QUrl sarvamEndpoint;
    };

    explicit Backend(const Options &options, QObject *parent = nullptr);
    Backend() : Backend(Options{}) {}

    QString state() const;
    bool recording() const { return m_recorder.isRecording(); }
    bool processing() const { return m_processing; }
    bool indicatorVisible() const { return m_indicator && (recording() || m_processing); }
    double level() const { return m_recorder.level(); }
    QString durationText() const { return History::formatDuration(m_recorder.duration()); }
    QString transcript() const { return m_transcript; }
    QString lastError() const { return m_lastError; }
    bool canTranscribe() const;
    QString notReadyMessage() const;
    bool whisperAvailable() const { return Whisper::available(); }

    QString engine() const { return m_engine; }
    void setEngine(const QString &engine);
    QString model() const { return m_model; }
    void setModel(const QString &model);
    QString language() const { return m_language; }
    void setLanguage(const QString &language);
    QString sarvamMode() const { return m_sarvamMode; }
    void setSarvamMode(const QString &mode);
    bool hasSarvamKey() const { return !m_sarvamKey.isEmpty(); }
    bool keyringAvailable() const { return m_secrets.available(); }
    QString microphone() const { return m_microphone; }
    void setMicrophone(const QString &id);
    bool autoPaste() const { return m_autoPaste; }
    void setAutoPaste(bool enabled);
    bool sounds() const { return m_sounds; }
    void setSounds(bool enabled);
    bool launchAtLogin() const { return m_launchAtLogin; }
    void setLaunchAtLogin(bool enabled);

    QVariantList dictionary() const { return Dictionary::toVariant(m_rules); }
    QVariantList models() const { return m_models.list(); }
    QVariantList microphones() const { return m_recorder.devices(); }
    QVariantList languages() const;
    int historyRevision() const { return m_historyRevision; }
    int historyCount() const { return int(m_history.entries().size()); }

    // The dictation keys. Text from these is pasted at the cursor.
    void dictationStart();
    void dictationStop();
    void dictationToggle();

    // The window's record button: the transcript stays in the window.
    Q_INVOKABLE void toggleRecording();
    // Throws the current recording away.
    Q_INVOKABLE void cancelRecording();
    Q_INVOKABLE void copyTranscript();
    Q_INVOKABLE void dismissError();

    Q_INVOKABLE void pickFile();
    Q_INVOKABLE void transcribeUrl(const QUrl &url);
    void transcribeFile(const QString &path, Delivery delivery, Done done = {});

    // False when the keyring refused the key.
    Q_INVOKABLE bool saveSarvamKey(const QString &key);
    Q_INVOKABLE void addRule(const QString &from, const QString &to);
    Q_INVOKABLE void removeRule(int index);
    Q_INVOKABLE void downloadModel(const QString &id);
    Q_INVOKABLE void cancelDownload();
    Q_INVOKABLE void removeModel(const QString &id);

    Q_INVOKABLE QVariantList history(const QString &query) const { return m_history.search(query); }
    Q_INVOKABLE void copyHistory(const QString &id);
    Q_INVOKABLE void deleteHistory(const QString &id);
    Q_INVOKABLE void clearHistory();
    Q_INVOKABLE void exportHistory(const QString &id, const QString &format);

    // Warm the engine for the first dictation.
    void prepare();

    // Tests swap in a picker that answers without a dialog.
    void setFilePicker(FilePicker *picker);

signals:
    void stateChanged();
    void levelChanged();
    void durationChanged();
    void transcriptChanged();
    void lastErrorChanged();
    void settingsChanged();
    void dictionaryChanged();
    void modelsChanged();
    void microphonesChanged();
    void historyChanged();
    // Shown briefly in the window ("Copied").
    void flashed(const QString &message);

private:
    void startRecording(bool indicator);
    void finishRecording(Delivery delivery);
    void perform(const QVector<float> &samples, Done done);
    void performLocal(const QVector<float> &samples, Done done);
    void deliver(const QString &text, const QString &error, double duration, const QString &sourceFile,
                 Delivery delivery, const Done &done);
    void fail(const QString &message);
    void setProcessing(bool processing);
    void warm();
    void saveRules();
    QString whisperPrompt() const;

    Options m_options;
    QSettings m_settings;
    QString m_dictionaryPath;
    SecretStore m_secrets;
    Recorder m_recorder;
    Models m_models;
    History m_history;
    Whisper m_whisper;
    Sarvam m_sarvam;
    Inserter m_inserter;
    Notifier m_notifier;
    FilePicker *m_picker = nullptr;

    QString m_engine, m_model, m_language, m_sarvamMode, m_sarvamKey, m_microphone;
    bool m_autoPaste = true, m_sounds = true, m_launchAtLogin = false;
    QList<DictionaryRule> m_rules;

    bool m_processing = false;
    // Whether this recording shows the floating pill (dictation keys do,
    // the window's button doesn't).
    bool m_indicator = false;
    QString m_transcript, m_lastError, m_pendingExport;
    int m_historyRevision = 0;
};
