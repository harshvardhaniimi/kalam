#include "backend.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUuid>
#include <QVariantMap>

#include "audio.h"
#include "portalfilepicker.h"

namespace {
QString configDirectory(const Backend::Options &options) {
    return options.configDirectory.isEmpty()
               ? QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + "/kalam"
               : options.configDirectory;
}

QString dataDirectory(const Backend::Options &options) {
    return options.dataDirectory.isEmpty()
               ? QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/kalam"
               : options.dataDirectory;
}

// Less than this is a stray key press, not something to transcribe.
constexpr qsizetype minimumSamples = Audio::sampleRate * 3 / 10;
}

Backend::Backend(const Options &options, QObject *parent)
    : QObject(parent),
      m_options(options),
      m_settings(configDirectory(options) + "/kalam.conf", QSettings::IniFormat),
      m_dictionaryPath(configDirectory(options) + "/dictionary.json"),
      m_secrets(options.secretTool),
      m_models(dataDirectory(options) + "/models"),
      m_history(dataDirectory(options) + "/history.json"),
      m_sarvam(options.sarvamEndpoint.isEmpty() ? QUrl("https://api.sarvam.ai/speech-to-text") : options.sarvamEndpoint) {
    // Sarvam is the default engine; Local Whisper is there for whoever
    // wants it, and downloads a model only when asked to.
    m_engine = m_settings.value("engine", "sarvam").toString() == "local" ? "local" : "sarvam";
    m_model = m_settings.value("model", "base").toString();
    if (!Models::isKnown(m_model))
        m_model = "base";
    m_language = m_settings.value("language", "auto").toString();
    m_sarvamMode = m_settings.value("sarvamMode", "codemix").toString() == "transcribe" ? "transcribe" : "codemix";
    m_microphone = m_settings.value("microphone").toString();
    m_autoPaste = m_settings.value("autoPaste", true).toBool();
    m_sounds = m_settings.value("sounds", true).toBool();

    // The keyring first, then the environment for terminal launches.
    m_sarvamKey = m_secrets.load();
    if (m_sarvamKey.isEmpty())
        m_sarvamKey = qEnvironmentVariable("SARVAM_API_KEY").trimmed();

    QFile rules(m_dictionaryPath);
    if (rules.open(QIODevice::ReadOnly))
        m_rules = Dictionary::fromJson(rules.readAll());

    m_notifier.setSoundsEnabled(m_sounds);
    m_notifier.setMuted(options.oneShot);
    connect(&m_notifier, &Notifier::errorShown, this, [this](const QString &message) {
        m_lastError = message;
        emit lastErrorChanged();
    });

    connect(&m_recorder, &Recorder::levelChanged, this, &Backend::levelChanged);
    connect(&m_recorder, &Recorder::durationChanged, this, &Backend::durationChanged);
    connect(&m_recorder, &Recorder::devicesChanged, this, &Backend::microphonesChanged);
    // A recording the user didn't stop themselves is transcribed to the
    // clipboard: pasting at the cursor minutes later would land somewhere
    // unintended.
    connect(&m_recorder, &Recorder::autoStopped, this, [this](Recorder::AutoStop reason) {
        if (!recording())
            return;
        m_notifier.error(reason == Recorder::AutoStop::Silence
                             ? tr("Recording stopped after %1 minutes of silence.").arg(Recorder::silenceTimeoutSeconds / 60)
                         : reason == Recorder::AutoStop::MaxDuration
                             ? tr("Recording stopped at the %1-minute limit.").arg(Recorder::maxDurationSeconds / 60)
                             : tr("The microphone was disconnected, so the recording stopped."));
        finishRecording(Delivery::Clipboard);
    });

    connect(&m_models, &Models::changed, this, [this] {
        emit modelsChanged();
        emit settingsChanged();
    });
    connect(&m_models, &Models::downloadFinished, this, [this](const QString &id) {
        if (id == m_model)
            warm();
    });
    connect(&m_models, &Models::downloadFailed, this, [this](const QString &id, const QString &message) {
        m_notifier.error(tr("Could not download the %1 model: %2").arg(id, message));
    });
    connect(&m_history, &History::changed, this, [this] {
        ++m_historyRevision;
        emit historyChanged();
    });

    if (!options.oneShot) {
        QProcess enabled;
        enabled.start("systemctl", {"--user", "is-enabled", "kalam.service"});
        m_launchAtLogin = enabled.waitForFinished(2000) && enabled.exitCode() == 0;
        setFilePicker(new PortalFilePicker(this));
    }
}

void Backend::setFilePicker(FilePicker *picker) {
    if (m_picker)
        m_picker->deleteLater();
    m_picker = picker;
    connect(picker, &FilePicker::openSelected, this, &Backend::transcribeUrl);
    connect(picker, &FilePicker::failed, &m_notifier, &Notifier::error);
    connect(picker, &FilePicker::saveSelected, this, [this](const QUrl &url) {
        QSaveFile file(url.toLocalFile());
        if (file.open(QIODevice::WriteOnly) && file.write(m_pendingExport.toUtf8()) >= 0 && file.commit())
            emit flashed(tr("Exported"));
        else
            m_notifier.error(tr("Could not write %1.").arg(url.toLocalFile()));
        m_pendingExport.clear();
    });
}

QString Backend::state() const {
    return recording() ? "recording" : m_processing ? "transcribing" : "idle";
}

bool Backend::canTranscribe() const {
    return (m_engine == "sarvam" && !m_sarvamKey.isEmpty())
           || (m_models.isInstalled(m_model) && Whisper::available());
}

// Why nothing can be transcribed yet, for the engine that is selected.
QString Backend::notReadyMessage() const {
    if (m_engine == "sarvam")
        return tr("Add your Sarvam API key in Settings to start dictating.");
    if (!Whisper::available())
        return tr("whisper-server is not installed. Install the whisper-cpp package.");
    if (!m_models.downloading().isEmpty())
        return tr("The Whisper model is still downloading. Try again when it finishes.");
    return tr("Download a Whisper model in Settings to start dictating.");
}

QVariantList Backend::languages() const {
    static const QList<QPair<const char *, const char *>> codes{
        {"auto", QT_TR_NOOP("Auto Detect")}, {"en", "English"}, {"hi", "Hindi"}, {"es", "Spanish"},
        {"fr", "French"}, {"de", "German"}, {"it", "Italian"}, {"pt", "Portuguese"}, {"zh", "Chinese"},
        {"ja", "Japanese"}, {"ko", "Korean"}, {"ru", "Russian"}, {"ar", "Arabic"}, {"bn", "Bengali"},
        {"ta", "Tamil"}, {"te", "Telugu"}, {"mr", "Marathi"}, {"gu", "Gujarati"}, {"kn", "Kannada"},
        {"ml", "Malayalam"}, {"pa", "Punjabi"}, {"ur", "Urdu"}, {"nl", "Dutch"}, {"tr", "Turkish"},
        {"pl", "Polish"}, {"sv", "Swedish"}, {"id", "Indonesian"}, {"th", "Thai"}, {"vi", "Vietnamese"},
        {"he", "Hebrew"}, {"uk", "Ukrainian"}, {"ms", "Malay"}, {"cs", "Czech"}, {"ro", "Romanian"},
        {"da", "Danish"}, {"el", "Greek"}};
    QVariantList list;
    for (const auto &[code, name] : codes)
        list.append(QVariantMap{{"code", code}, {"name", tr(name)}});
    return list;
}

// MARK: settings

void Backend::setEngine(const QString &engine) {
    if (engine == m_engine || (engine != "local" && engine != "sarvam"))
        return;
    m_engine = engine;
    m_settings.setValue("engine", engine);
    emit settingsChanged();
    warm();
}

void Backend::setModel(const QString &model) {
    if (model == m_model || !Models::isKnown(model))
        return;
    m_model = model;
    m_settings.setValue("model", model);
    emit settingsChanged();
    warm();
}

void Backend::setLanguage(const QString &language) {
    if (language == m_language)
        return;
    m_language = language;
    m_settings.setValue("language", language);
    emit settingsChanged();
}

void Backend::setSarvamMode(const QString &mode) {
    if (mode == m_sarvamMode || (mode != "codemix" && mode != "transcribe"))
        return;
    m_sarvamMode = mode;
    m_settings.setValue("sarvamMode", mode);
    emit settingsChanged();
}

void Backend::setMicrophone(const QString &id) {
    if (id == m_microphone)
        return;
    m_microphone = id;
    m_settings.setValue("microphone", id);
    emit settingsChanged();
}

void Backend::setAutoPaste(bool enabled) {
    if (enabled == m_autoPaste)
        return;
    m_autoPaste = enabled;
    m_settings.setValue("autoPaste", enabled);
    emit settingsChanged();
}

void Backend::setSounds(bool enabled) {
    if (enabled == m_sounds)
        return;
    m_sounds = enabled;
    m_settings.setValue("sounds", enabled);
    m_notifier.setSoundsEnabled(enabled);
    emit settingsChanged();
}

void Backend::setLaunchAtLogin(bool enabled) {
    if (enabled == m_launchAtLogin)
        return;
    QProcess process;
    process.start("systemctl", {"--user", enabled ? "enable" : "disable", "kalam.service"});
    if (process.waitForFinished(5000) && process.exitCode() == 0)
        m_launchAtLogin = enabled;
    else
        m_notifier.error(tr("Could not change the login setting: %1")
                             .arg(QString::fromUtf8(process.readAllStandardError()).trimmed()));
    emit settingsChanged();
}

bool Backend::saveSarvamKey(const QString &key) {
    const QString trimmed = key.trimmed();
    if (!m_secrets.save(trimmed)) {
        m_notifier.error(tr("Could not save the key to the keyring."));
        return false;
    }
    m_sarvamKey = trimmed;
    emit settingsChanged();
    return true;
}

void Backend::saveRules() {
    QDir().mkpath(QFileInfo(m_dictionaryPath).absolutePath());
    QSaveFile file(m_dictionaryPath);
    if (!file.open(QIODevice::WriteOnly) || file.write(Dictionary::toJson(m_rules)) < 0 || !file.commit())
        m_notifier.error(tr("Could not write %1.").arg(m_dictionaryPath));
    emit dictionaryChanged();
}

void Backend::addRule(const QString &from, const QString &to) {
    if (from.trimmed().isEmpty() || to.trimmed().isEmpty())
        return;
    m_rules.append({from.trimmed(), to.trimmed()});
    saveRules();
}

void Backend::removeRule(int index) {
    if (index < 0 || index >= m_rules.size())
        return;
    m_rules.removeAt(index);
    saveRules();
}

void Backend::downloadModel(const QString &id) {
    m_models.download(id);
}

void Backend::cancelDownload() {
    m_models.cancel();
}

void Backend::removeModel(const QString &id) {
    if (id == m_model)
        m_whisper.unload();
    m_models.remove(id);
}

// MARK: engines

void Backend::prepare() {
    if (m_engine == "local" && !Whisper::available())
        m_notifier.error(tr("whisper-server is not installed. Install the whisper-cpp package."));
    warm();
}

// Keep the selected model loaded while Local Whisper is the engine, so a
// dictation doesn't wait on a model load. Sarvam only needs it as a
// fallback, which can load on demand.
void Backend::warm() {
    if (m_options.oneShot)
        return;
    if (m_engine == "local" && m_models.isInstalled(m_model) && Whisper::available())
        m_whisper.load(m_models.path(m_model));
    else if (m_engine != "local")
        m_whisper.unload();
}

// Whisper spells names better when it has seen them; the dictionary's
// corrected forms are exactly the words it keeps getting wrong.
QString Backend::whisperPrompt() const {
    QStringList words;
    for (const auto &rule : m_rules)
        if (!words.contains(rule.to))
            words.append(rule.to);
    return words.isEmpty() ? QString() : words.join(", ").left(400);
}

void Backend::performLocal(const QVector<float> &samples, Done done) {
    if (!m_models.isInstalled(m_model)) {
        done({}, notReadyMessage());
        return;
    }
    m_whisper.transcribe(samples, m_models.path(m_model), m_language, whisperPrompt(),
                         [this, done](const QString &text, const QString &error) {
                             done(error.isEmpty() ? Dictionary::apply(text, m_rules) : QString(), error);
                         });
}

// Route through the selected engine. If Sarvam fails (offline, bad key, API
// error) and a local model is installed, fall back to it so a network blip
// never eats a recording.
void Backend::perform(const QVector<float> &samples, Done done) {
    if (m_engine != "sarvam") {
        performLocal(samples, std::move(done));
        return;
    }
    m_sarvam.transcribe(samples, m_sarvamKey, m_sarvamMode,
                        [this, samples, done](const QString &text, const QString &error) {
                            if (error.isEmpty()) {
                                done(Dictionary::apply(text, m_rules), {});
                            } else if (m_models.isInstalled(m_model) && Whisper::available()) {
                                m_notifier.error(tr("%1 Falling back to local Whisper.").arg(error));
                                performLocal(samples, done);
                            } else {
                                done({}, error);
                            }
                        });
}

// MARK: recording

void Backend::setProcessing(bool processing) {
    m_processing = processing;
    emit stateChanged();
}

void Backend::fail(const QString &message) {
    m_notifier.error(message);
}

void Backend::dismissError() {
    m_lastError.clear();
    emit lastErrorChanged();
}

void Backend::startRecording(bool indicator) {
    if (recording())
        return;
    if (m_processing) {
        // Acknowledge the press so it doesn't feel dead.
        m_notifier.cue(Notifier::Cue::Error);
        return;
    }
    if (!canTranscribe()) {
        fail(notReadyMessage());
        return;
    }
    const QString problem = m_recorder.start(m_microphone);
    if (!problem.isEmpty()) {
        fail(problem);
        return;
    }
    m_indicator = indicator;
    m_transcript.clear();
    dismissError();
    emit transcriptChanged();
    emit stateChanged();
    m_notifier.cue(Notifier::Cue::Start);
}

void Backend::finishRecording(Delivery delivery) {
    if (!recording())
        return;
    const QVector<float> samples = m_recorder.stop();
    const double duration = m_recorder.duration();
    if (samples.size() < minimumSamples) {
        emit stateChanged();
        fail(tr("No audio was captured. Check your microphone input."));
        return;
    }
    m_notifier.cue(Notifier::Cue::Stop);
    setProcessing(true);
    perform(samples, [this, duration, delivery](const QString &text, const QString &error) {
        deliver(text, error, duration, {}, delivery, {});
    });
}

void Backend::deliver(const QString &text, const QString &error, double duration, const QString &sourceFile,
                      Delivery delivery, const Done &done) {
    setProcessing(false);
    if (!error.isEmpty()) {
        fail(error);
        if (done)
            done({}, error);
        return;
    }

    m_transcript = text;
    emit transcriptChanged();
    if (!m_history.add({QUuid::createUuid().toString(QUuid::WithoutBraces), text, QDateTime::currentDateTimeUtc(),
                        duration, m_language, sourceFile}))
        fail(tr("The transcript could not be saved to history."));

    const QString preview = text.size() > 100 ? text.left(100) + "…" : text;
    switch (delivery) {
    case Delivery::Paste: {
        const auto result = m_autoPaste ? m_inserter.insert(text)
                          : m_inserter.copy(text) ? Inserter::Result::CopiedOnly : Inserter::Result::Failed;
        if (result == Inserter::Result::Failed)
            fail(tr("The transcript could not be copied to the clipboard. It is saved in History."));
        else if (result == Inserter::Result::CopiedOnly)
            m_notifier.info(tr("Copied to the clipboard"), preview);
        m_notifier.cue(Notifier::Cue::Done);
        break;
    }
    case Delivery::Clipboard:
        if (m_inserter.copy(text))
            m_notifier.info(tr("Transcription complete, copied to the clipboard"), preview);
        else
            fail(tr("The transcript could not be copied to the clipboard. It is saved in History."));
        m_notifier.cue(Notifier::Cue::Done);
        break;
    case Delivery::Window:
        m_notifier.cue(Notifier::Cue::Done);
        break;
    case Delivery::CommandLine:
        break;
    }
    if (done)
        done(text, {});
}

void Backend::dictationStart() {
    startRecording(true);
}

void Backend::dictationStop() {
    finishRecording(Delivery::Paste);
}

void Backend::dictationToggle() {
    if (recording())
        dictationStop();
    else
        dictationStart();
}

void Backend::toggleRecording() {
    if (recording())
        // A recording begun with the dictation keys still pastes when it is
        // ended from the window.
        finishRecording(m_indicator ? Delivery::Paste : Delivery::Window);
    else
        startRecording(false);
}

void Backend::cancelRecording() {
    if (!recording())
        return;
    m_recorder.stop();
    emit stateChanged();
}

void Backend::copyTranscript() {
    if (!m_transcript.isEmpty() && m_inserter.copy(m_transcript))
        emit flashed(tr("Copied"));
}

// MARK: files

void Backend::pickFile() {
    if (m_picker)
        m_picker->openAudio();
}

void Backend::transcribeUrl(const QUrl &url) {
    transcribeFile(url.toLocalFile(), Delivery::Clipboard);
}

void Backend::transcribeFile(const QString &path, Delivery delivery, Done done) {
    auto refuse = [&](const QString &message) {
        if (delivery != Delivery::CommandLine)
            fail(message);
        if (done)
            done({}, message);
    };
    if (!QFileInfo(path).isFile())
        return refuse(tr("%1 is not a file.").arg(path));
    if (recording() || m_processing)
        return refuse(tr("Kalam is already recording or transcribing. Try the file again when it finishes."));
    if (!canTranscribe())
        return refuse(notReadyMessage());
    const QString ffmpeg = QStandardPaths::findExecutable("ffmpeg");
    if (ffmpeg.isEmpty())
        return refuse(tr("ffmpeg is not installed, so audio files can't be read."));

    m_indicator = false;
    m_transcript.clear();
    emit transcriptChanged();
    dismissError();
    setProcessing(true);

    // ffmpeg reads anything with an audio track (video containers too) and
    // hands back exactly what the engines want: 16 kHz mono float.
    auto *decoder = new QProcess(this);
    auto bytes = std::make_shared<QByteArray>();
    connect(decoder, &QProcess::readyReadStandardOutput, this,
            [decoder, bytes] { bytes->append(decoder->readAllStandardOutput()); });
    connect(decoder, &QProcess::finished, this, [=, this](int code, QProcess::ExitStatus status) {
        decoder->deleteLater();
        bytes->append(decoder->readAllStandardOutput());
        const QVector<float> samples = Audio::fromFloat32(*bytes);
        QString problem;
        if (code != 0 || status != QProcess::NormalExit)
            problem = tr("Kalam couldn't read that file: %1")
                          .arg(QString::fromUtf8(decoder->readAllStandardError()).trimmed().section('\n', -1));
        else if (samples.size() < minimumSamples)
            problem = tr("That file has no audio to transcribe.");
        if (!problem.isEmpty()) {
            setProcessing(false);
            if (delivery != Delivery::CommandLine)
                fail(problem);
            if (done)
                done({}, problem);
            return;
        }
        const double duration = double(samples.size()) / Audio::sampleRate;
        const QString name = QFileInfo(path).fileName();
        perform(samples, [=, this](const QString &text, const QString &error) {
            // A command-line caller reports its own errors.
            if (delivery == Delivery::CommandLine && !error.isEmpty()) {
                setProcessing(false);
                if (done)
                    done({}, error);
                return;
            }
            deliver(text, error, duration, name, delivery, done);
        });
    });
    decoder->start(ffmpeg, {"-v", "error", "-nostdin", "-i", path, "-vn", "-ac", "1", "-ar",
                            QString::number(Audio::sampleRate), "-f", "f32le", "-"});
}

// MARK: history

void Backend::copyHistory(const QString &id) {
    const QString text = m_history.exportAs(id, "text").trimmed();
    if (!text.isEmpty() && m_inserter.copy(text))
        emit flashed(tr("Copied"));
}

void Backend::deleteHistory(const QString &id) {
    if (!m_history.remove(id))
        fail(tr("The history file could not be updated."));
}

void Backend::clearHistory() {
    if (!m_history.clear())
        fail(tr("The history file could not be updated."));
}

void Backend::exportHistory(const QString &id, const QString &format) {
    m_pendingExport = m_history.exportAs(id, format);
    if (m_pendingExport.isEmpty() || !m_picker)
        return;
    const QString extension = format == "markdown" ? "md" : format == "json" ? "json" : format == "srt" ? "srt" : "txt";
    m_picker->saveText("transcription-" + QDateTime::currentDateTime().toString("yyyyMMdd-HHmm") + "." + extension);
}
