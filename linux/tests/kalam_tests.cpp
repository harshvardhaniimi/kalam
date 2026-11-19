#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QStandardPaths>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QtTest>
#include <cmath>

#include "audio.h"
#include "backend.h"
#include "dictionary.h"
#include "history.h"
#include "inserter.h"
#include "models.h"
#include "sarvam.h"
#include "secretstore.h"
#include "theme.h"
#include "translator.h"
#include "whisper.h"

// Stands in for Sarvam's endpoint: records each request and answers with
// the next canned reply.
class FakeSarvam : public QObject {
public:
    struct Reply {
        int status;
        QByteArray body;
    };

    FakeSarvam() {
        server.listen(QHostAddress::LocalHost, 0);
        connect(&server, &QTcpServer::newConnection, this, [this] {
            QTcpSocket *socket = server.nextPendingConnection();
            auto buffer = std::make_shared<QByteArray>();
            connect(socket, &QTcpSocket::readyRead, this, [this, socket, buffer] {
                buffer->append(socket->readAll());
                const qsizetype split = buffer->indexOf("\r\n\r\n");
                if (split < 0)
                    return;
                const QByteArray head = buffer->left(split).toLower();
                const qsizetype at = head.indexOf("content-length:");
                const qsizetype length = head.mid(at + 15, head.indexOf('\r', at) - at - 15).trimmed().toLongLong();
                if (buffer->size() - split - 4 < length)
                    return;
                requests.append(*buffer);
                buffer->clear();
                const Reply reply = replies.isEmpty() ? Reply{200, R"({"transcript":"ok"})"} : replies.takeFirst();
                socket->write("HTTP/1.1 " + QByteArray::number(reply.status) + " X\r\nContent-Type: application/json\r\n"
                              "Connection: close\r\nContent-Length: " + QByteArray::number(reply.body.size()) + "\r\n\r\n"
                              + reply.body);
                socket->disconnectFromHost();
            });
        });
    }

    QUrl url() const { return QUrl(QString("http://127.0.0.1:%1/speech-to-text").arg(server.serverPort())); }

    QTcpServer server;
    QList<Reply> replies;
    QList<QByteArray> requests;
};

class KalamTests : public QObject {
    Q_OBJECT

private slots:
    // MARK: audio

    void wavHasACorrectHeader()
    {
        const QByteArray wav = Audio::makeWav(QVector<float>{0.0f, 1.0f, -1.0f, 2.0f});
        QCOMPARE(wav.size(), 44 + 8);
        QCOMPARE(wav.left(4), QByteArray("RIFF"));
        QCOMPARE(wav.mid(8, 8), QByteArray("WAVEfmt "));
        QCOMPARE(qFromLittleEndian<quint32>(wav.constData() + 24), quint32(16000));
        QCOMPARE(qFromLittleEndian<quint32>(wav.constData() + 40), quint32(8));
        // Full scale, and anything past it is clamped rather than wrapped.
        QCOMPARE(qFromLittleEndian<qint16>(wav.constData() + 46), qint16(32767));
        QCOMPARE(qFromLittleEndian<qint16>(wav.constData() + 48), qint16(-32767));
        QCOMPARE(qFromLittleEndian<qint16>(wav.constData() + 50), qint16(32767));
    }

    void chunksCoverEverySample()
    {
        const QVector<float> samples(16000 * 60 + 5, 0.1f);
        const auto pieces = Audio::chunks(samples, 25.0);
        QCOMPARE(pieces.size(), 3);
        QCOMPARE(pieces[0].size(), 16000 * 25);
        QCOMPARE(pieces[2].size(), 16000 * 10 + 5);
    }

    void resampleKeepsTheDuration()
    {
        const QVector<float> second(48000, 0.5f);
        const auto out = Audio::resample(second, 48000);
        QCOMPARE(out.size(), 16000);
        QVERIFY(std::abs(out[8000] - 0.5f) < 0.001f);
        QCOMPARE(Audio::resample(out, 16000).size(), 16000);
    }

    void levelRunsFromSilenceToFullScale()
    {
        const QVector<float> silence(1600, 0.0f), loud(1600, 1.0f);
        QCOMPARE(Audio::level(silence.constData(), silence.size()), 0.0f);
        QCOMPARE(Audio::level(loud.constData(), loud.size()), 1.0f);
    }

    // MARK: dictionary

    void dictionaryReplacesWholeWordsIgnoringCase()
    {
        const QList<DictionaryRule> rules{{"omarchi", "Omarchy"}, {"bda", "BDA"}};
        QCOMPARE(Dictionary::apply("I use OMARCHI for bda and bdaX", rules), QString("I use Omarchy for BDA and bdaX"));
    }

    void dictionaryPrefersTheLongestRule()
    {
        const QList<DictionaryRule> rules{{"sharjah", "Sharjah"}, {"american university of sharjah", "AUS"}};
        QCOMPARE(Dictionary::apply("at american university of sharjah", rules), QString("at AUS"));
    }

    void dictionaryHandlesDevanagariAndLiteralReplacements()
    {
        // "कल" must not match inside "कलम", whose next character is a mark
        // or letter.
        const QList<DictionaryRule> rules{{"कल", "kal"}, {"cost", "$1 & \\1"}};
        QCOMPARE(Dictionary::apply("कलम और कल", rules), QString("कलम और kal"));
        QCOMPARE(Dictionary::apply("the cost", rules), QString("the $1 & \\1"));
    }

    void dictionaryRoundTripsThroughJson()
    {
        const QList<DictionaryRule> rules{{"a", "b"}, {"कल", "kal"}};
        const auto back = Dictionary::fromJson(Dictionary::toJson(rules));
        QCOMPARE(back.size(), 2);
        QCOMPARE(back[1].from, QString("कल"));
    }

    // MARK: history

    void historyPersistsSearchesAndExports()
    {
        QTemporaryDir dir;
        const QString path = dir.filePath("nested/history.json");
        {
            History history(path);
            QVERIFY(history.add({"1", "first note about Sharjah", QDateTime::currentDateTimeUtc(), 65, "auto", {}}));
            QVERIFY(history.add({"2", "दूसरा नोट", QDateTime::currentDateTimeUtc(), 5, "hi", "clip.mp3"}));
        }
        History history(path);
        QCOMPARE(history.entries().size(), 2);
        // Newest first.
        QCOMPARE(history.entries().first().id, QString("2"));
        QCOMPARE(history.search("sharjah").size(), 1);
        QCOMPARE(history.search("").size(), 2);
        QCOMPARE(history.search("नोट").first().toMap().value("sourceFile").toString(), QString("clip.mp3"));

        QCOMPARE(history.exportAs("1", "text"), QString("first note about Sharjah\n"));
        QVERIFY(history.exportAs("1", "markdown").contains("**Duration:** 01:05"));
        QVERIFY(history.exportAs("1", "srt").startsWith("1\n00:00:00,000 --> 00:01:05,000\n"));
        QCOMPARE(QJsonDocument::fromJson(history.exportAs("2", "json").toUtf8()).object().value("language").toString(),
                 QString("hi"));

        QVERIFY(history.remove("1"));
        QCOMPARE(History(path).entries().size(), 1);
        QVERIFY(history.clear());
        QCOMPARE(History(path).entries().size(), 0);
    }

    // MARK: delivery

    void terminalsPasteWithShift()
    {
        QVERIFY(Inserter::pasteArguments({"terminal*", "transparent-window*"}).contains("shift"));
        QVERIFY(!Inserter::pasteArguments({"browser"}).contains("shift"));
        QVERIFY(!Inserter::pasteArguments({}).contains("shift"));
    }

    void whisperMarkersAreNotSpeech()
    {
        QCOMPARE(Whisper::clean(" [BLANK_AUDIO] "), QString());
        QCOMPARE(Whisper::clean("Hello [MUSIC]\n there (silence)"), QString("Hello there"));
        QCOMPARE(Whisper::clean("keep (this) aside"), QString("keep (this) aside"));
    }

    void modelsAreInstalledOnlyWhenWhole()
    {
        QTemporaryDir dir;
        Models models(dir.path());
        QVERIFY(Models::isKnown("turbo"));
        QVERIFY(!Models::isKnown("huge"));
        QVERIFY(!models.isInstalled("base"));
        QCOMPARE(models.path("turbo"), dir.filePath("ggml-large-v3-turbo.bin"));

        // A stub left by a failed download is not a model.
        write(models.path("base"), "tiny");
        QVERIFY(!models.isInstalled("base"));
        write(models.path("base"), QByteArray(2 * 1024 * 1024, 'x'));
        QVERIFY(models.isInstalled("base"));
        QVERIFY(models.remove("base"));
        QVERIFY(!models.isInstalled("base"));
    }

    // MARK: Sarvam

    void sarvamSendsTheKeyAndJoinsChunks()
    {
        FakeSarvam fake;
        fake.replies = {{200, R"({"transcript":" namaste "})"}, {200, R"({"transcript":""})"}, {200, R"({"transcript":"world"})"}};
        Sarvam sarvam(fake.url());
        QString text, error;
        bool finished = false;
        sarvam.transcribe(QVector<float>(16000 * 60, 0.1f), "  secret-key\n", "codemix", [&](const QString &t, const QString &e) {
            text = t;
            error = e;
            finished = true;
        });
        QTRY_VERIFY_WITH_TIMEOUT(finished, 10000);
        QCOMPARE(error, QString());
        QCOMPARE(text, QString("namaste world"));
        // 60 seconds is three requests of at most 25 seconds each.
        QCOMPARE(fake.requests.size(), 3);
        const QByteArray &request = fake.requests.first();
        QVERIFY(request.toLower().contains("api-subscription-key: secret-key\r\n"));
        QVERIFY(request.contains("name=\"model\"\r\n\r\nsaaras:v3"));
        QVERIFY(request.contains("name=\"mode\"\r\n\r\ncodemix"));
        QVERIFY(request.contains("name=\"language_code\"\r\n\r\nunknown"));
        QVERIFY(request.contains("filename=\"audio.wav\""));
        QVERIFY(request.contains("RIFF"));
    }

    void sarvamReportsApiErrorsAndMissingKeys()
    {
        FakeSarvam fake;
        fake.replies = {{403, R"({"error":"invalid key"})"}};
        Sarvam sarvam(fake.url());
        QString error;
        sarvam.transcribe(QVector<float>(16000, 0.1f), "bad", "codemix", [&](const QString &, const QString &e) { error = e; });
        QTRY_VERIFY_WITH_TIMEOUT(!error.isEmpty(), 10000);
        QVERIFY2(error.contains("403") && error.contains("invalid key"), qPrintable(error));

        error.clear();
        sarvam.transcribe(QVector<float>(16000, 0.1f), "  ", "codemix", [&](const QString &, const QString &e) { error = e; });
        QVERIFY(error.contains("API key"));
        QCOMPARE(fake.requests.size(), 1);

        // Speech the API hears nothing in is an error, not an empty paste.
        fake.replies = {{200, R"({"transcript":""})"}};
        error.clear();
        sarvam.transcribe(QVector<float>(16000, 0.1f), "key", "codemix", [&](const QString &, const QString &e) { error = e; });
        QTRY_VERIFY_WITH_TIMEOUT(!error.isEmpty(), 10000);
    }

    // MARK: backend

    void backendDefaultsToSarvamAndNeedsAKey()
    {
        QTemporaryDir dir;
        Backend backend(options(dir));
        QCOMPARE(backend.engine(), QString("sarvam"));
        QCOMPARE(backend.sarvamMode(), QString("codemix"));
        QVERIFY(!backend.hasSarvamKey());
        QVERIFY(!backend.canTranscribe());
        QVERIFY(backend.notReadyMessage().contains("Sarvam"));
        // No Whisper model is fetched unless the user asks for one.
        QVERIFY(QDir(dir.filePath("data/models")).isEmpty());
    }

    void backendKeepsTheKeyInTheKeyringAndSettingsOnDisk()
    {
        QTemporaryDir dir;
        {
            Backend backend(options(dir));
            QVERIFY(backend.saveSarvamKey(" my-key "));
            QVERIFY(backend.hasSarvamKey());
            QVERIFY(backend.canTranscribe());
            backend.setSarvamMode("transcribe");
            backend.setLanguage("hi");
            backend.setAutoPaste(false);
            backend.addRule("omarchi", "Omarchy");
            backend.addRule("  ", "ignored");
        }
        // The key is in the (fake) keyring, never in the settings file.
        QCOMPARE(read(dir.filePath("keyring")), QByteArray("my-key"));
        QVERIFY(!read(dir.filePath("config/kalam.conf")).contains("my-key"));

        Backend backend(options(dir));
        QVERIFY(backend.hasSarvamKey());
        QCOMPARE(backend.sarvamMode(), QString("transcribe"));
        QCOMPARE(backend.language(), QString("hi"));
        QVERIFY(!backend.autoPaste());
        QCOMPARE(backend.dictionary().size(), 1);

        QVERIFY(backend.saveSarvamKey(""));
        QVERIFY(!backend.hasSarvamKey());
        QVERIFY(!QFile::exists(dir.filePath("keyring")));
    }

    void backendTranscribesAFileThroughSarvam()
    {
        if (QStandardPaths::findExecutable("ffmpeg").isEmpty())
            QSKIP("ffmpeg is not installed");
        QTemporaryDir dir;
        const QString clip = dir.filePath("clip.wav");
        QVector<float> tone(16000 * 2);
        for (int i = 0; i < tone.size(); ++i)
            tone[i] = 0.3f * float(std::sin(i * 0.05));
        write(clip, Audio::makeWav(tone));

        FakeSarvam fake;
        fake.replies = {{200, R"({"transcript":"hello omarchi"})"}};
        auto opts = options(dir);
        opts.sarvamEndpoint = fake.url();
        Backend backend(opts);
        QVERIFY(backend.saveSarvamKey("key"));
        backend.addRule("omarchi", "Omarchy");

        QString text, error;
        bool finished = false;
        backend.transcribeFile(clip, Backend::Delivery::CommandLine, [&](const QString &t, const QString &e) {
            text = t;
            error = e;
            finished = true;
        });
        QVERIFY(backend.processing());
        QTRY_VERIFY_WITH_TIMEOUT(finished, 20000);
        QCOMPARE(error, QString());
        // The personal dictionary applies to Sarvam's transcript too.
        QCOMPARE(text, QString("hello Omarchy"));
        QVERIFY(!backend.processing());
        QCOMPARE(backend.transcript(), QString("hello Omarchy"));
        QCOMPARE(backend.historyCount(), 1);
        QCOMPARE(backend.history("").first().toMap().value("sourceFile").toString(), QString("clip.wav"));
        QCOMPARE(backend.history("").first().toMap().value("duration").toString(), QString("00:02"));
    }

    void backendReportsAFailedTranscriptionWithoutSavingIt()
    {
        if (QStandardPaths::findExecutable("ffmpeg").isEmpty())
            QSKIP("ffmpeg is not installed");
        QTemporaryDir dir;
        const QString clip = dir.filePath("clip.wav");
        write(clip, Audio::makeWav(QVector<float>(16000, 0.2f)));
        write(dir.filePath("notes.txt"), "not audio");

        FakeSarvam fake;
        fake.replies = {{500, "boom"}};
        auto opts = options(dir);
        opts.sarvamEndpoint = fake.url();
        Backend backend(opts);
        QVERIFY(backend.saveSarvamKey("key"));

        QString error;
        backend.transcribeFile(clip, Backend::Delivery::CommandLine, [&](const QString &, const QString &e) { error = e; });
        QTRY_VERIFY_WITH_TIMEOUT(!error.isEmpty(), 20000);
        QVERIFY2(error.contains("500"), qPrintable(error));
        QCOMPARE(backend.historyCount(), 0);
        QVERIFY(!backend.processing());

        error.clear();
        backend.transcribeFile(dir.filePath("notes.txt"), Backend::Delivery::CommandLine,
                               [&](const QString &, const QString &e) { error = e; });
        QTRY_VERIFY_WITH_TIMEOUT(!error.isEmpty(), 20000);
        QVERIFY(!backend.processing());
        QCOMPARE(fake.requests.size(), 1);
    }

    // MARK: theme and translator

    void themeFallsBack()
    {
        QTemporaryDir dir;
        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QString("#FFD60A"));
        QCOMPARE(theme.accentForeground(), QString("black"));
    }

    void themeReadsAccent()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("theme");
        write(dir.path() + "/theme/colors.toml", "accent = \"#112233\"\n");
        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QString("#112233"));
        QCOMPARE(theme.accentForeground(), QString("white"));
    }

    void themeFollowsHyprlandRounding()
    {
        QTemporaryDir dir;
        const QString response = dir.filePath("response.json"), command = dir.filePath("hyprctl");
        write(command, "#!/bin/sh\ncat '" + response.toUtf8() + "'\n");
        QVERIFY(QFile::setPermissions(command, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
        write(response, "{\"int\":0}");

        Theme theme(dir.path(), nullptr, command);
        QCOMPARE(theme.radius(), 0);
        write(response, "{\"int\":6}");
        QTRY_COMPARE(theme.radius(), 6);
    }

    void translatorFallsBackToEnglish()
    {
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.language(), QString("en"));
        QVERIFY(translator.translate("Main", "Save").isNull());
    }

    void translatorFollowsTheLanguageFile()
    {
        QTemporaryDir dir;
        write(dir.path() + "/language", "pt-BR\n");
        write(dir.path() + "/pt.json", R"({"Save": "Guardar", "Open": "Abrir"})");
        write(dir.path() + "/pt-BR.json", R"({"Save": "Salvar"})");

        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.language(), QString("pt-BR"));
        QCOMPARE(translator.translate("Main", "Save"), QString("Salvar"));
        QCOMPARE(translator.translate("Main", "Open"), QString("Abrir"));
        QVERIFY(translator.translate("Main", "Quit").isNull());
    }

    void shippedCatalogsAreValidAndCoverTheSameStrings()
    {
        // Every Hindi key must be a string the app really uses, or a stale
        // translation hides an untranslated one.
        const QString source = QFINDTESTDATA("../src");
        QByteArray code;
        for (const auto &name : QDir(source).entryList({"*.qml", "*.cpp", "*.h"}))
            code += read(source + "/" + name);
        const QJsonDocument hindi = QJsonDocument::fromJson(read(source + "/i18n/hi.json"));
        QVERIFY(hindi.isObject());
        const QJsonObject strings = hindi.object();
        for (auto it = strings.begin(); it != strings.end(); ++it) {
            QString key = it.key();
            key.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n");
            QVERIFY2(code.contains(key.toUtf8()), qPrintable("Unused translation: " + it.key()));
        }
        QVERIFY(QJsonDocument::fromJson(read(source + "/i18n/en.json")).isObject());
    }

private:
    // Temp directories for everything, and a fake secret-tool that keeps
    // the "keyring" in a file.
    static Backend::Options options(const QTemporaryDir &dir)
    {
        const QString tool = dir.filePath("secret-tool"), keyring = dir.filePath("keyring");
        if (!QFile::exists(tool)) {
            write(tool, "#!/bin/sh\ncase \"$1\" in\n"
                        "  store) cat > '" + keyring.toUtf8() + "' ;;\n"
                        "  lookup) [ -f '" + keyring.toUtf8() + "' ] && cat '" + keyring.toUtf8() + "' ;;\n"
                        "  clear) rm -f '" + keyring.toUtf8() + "' ;;\n"
                        "esac\n");
            QFile::setPermissions(tool, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        }
        Backend::Options options;
        options.oneShot = true;
        options.configDirectory = dir.filePath("config");
        options.dataDirectory = dir.filePath("data");
        options.secretTool = tool;
        return options;
    }

    static void write(const QString &path, const QByteArray &contents)
    {
        QDir().mkpath(QFileInfo(path).absolutePath());
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write(contents);
    }

    static QByteArray read(const QString &path)
    {
        QFile file(path);
        return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
    }
};

QTEST_MAIN(KalamTests)
#include "kalam_tests.moc"
