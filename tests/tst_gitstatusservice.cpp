#include <QTest>
#include <QProcess>
#include <QFileInfo>
#include <QStandardPaths>

#include "services/gitstatusservice.h"
#include "testdir.h"

// Reproduces GH #1: git status badges never render. The badge Loader keys off
// the model's gitStatus role, which is GitStatusService::statusForPath(). This
// test drives the service against a real temp repo with every dirty state, to
// isolate whether the C++ pipeline (rev-parse -> git status -> cache -> lookup)
// is the failing component or whether the bug lives in the QML delegate.
class TestGitStatusService : public QObject
{
    Q_OBJECT

    static bool gitAvailable()
    {
        return !QStandardPaths::findExecutable(QStringLiteral("git")).isEmpty();
    }

    // Run git synchronously in workdir. Returns true on exit code 0.
    static bool runGit(const QString &workdir, const QStringList &args)
    {
        QProcess p;
        p.setWorkingDirectory(workdir);
        p.start(QStringLiteral("git"), args);
        return p.waitForFinished(5000) && p.exitCode() == 0;
    }

    static QString abs(const QString &root, const QString &rel)
    {
        return QFileInfo(root + QLatin1Char('/') + rel).absoluteFilePath();
    }

private slots:
    void initTestCase()
    {
        if (!gitAvailable())
            QSKIP("git not in PATH");
    }

    void testStatusesForDirtyRepo()
    {
        TestDir repo;
        QVERIFY(repo.isValid());
        const QString root = repo.path();

        QVERIFY(runGit(root, {QStringLiteral("init"), QStringLiteral("-q")}));
        // Local identity + no signing so the commit never depends on the host's
        // global git config.
        runGit(root, {QStringLiteral("config"), QStringLiteral("user.email"), QStringLiteral("t@example.com")});
        runGit(root, {QStringLiteral("config"), QStringLiteral("user.name"), QStringLiteral("Test")});
        runGit(root, {QStringLiteral("config"), QStringLiteral("commit.gpgsign"), QStringLiteral("false")});

        // Baseline commit: a tracked file and a .gitignore.
        repo.createFile(QStringLiteral("tracked.txt"), "v1\n");
        repo.createFile(QStringLiteral(".gitignore"), "ignored.txt\n");
        QVERIFY(runGit(root, {QStringLiteral("add"), QStringLiteral("tracked.txt"), QStringLiteral(".gitignore")}));
        QVERIFY(runGit(root, {QStringLiteral("commit"), QStringLiteral("-q"), QStringLiteral("-m"), QStringLiteral("base")}));

        // Dirty states.
        repo.createFile(QStringLiteral("tracked.txt"), "v2\n");   // worktree-modified
        repo.createFile(QStringLiteral("untracked.txt"), "new\n"); // untracked
        repo.createFile(QStringLiteral("staged.txt"), "s\n");      // staged
        QVERIFY(runGit(root, {QStringLiteral("add"), QStringLiteral("staged.txt")}));
        repo.createFile(QStringLiteral("ignored.txt"), "x\n");     // ignored

        GitStatusService svc;
        svc.setRootPath(root);

        // setRootPath fires async rev-parse + git status (+80ms debounce).
        // Poll until the modified file resolves: proves the whole chain ran.
        QTRY_VERIFY_WITH_TIMEOUT(!svc.statusForPath(abs(root, QStringLiteral("tracked.txt"))).isEmpty(), 8000);

        QVERIFY(svc.isGitRepo());
        QCOMPARE(svc.statusForPath(abs(root, QStringLiteral("tracked.txt"))),   QStringLiteral("modified"));
        QCOMPARE(svc.statusForPath(abs(root, QStringLiteral("untracked.txt"))), QStringLiteral("untracked"));
        QCOMPARE(svc.statusForPath(abs(root, QStringLiteral("staged.txt"))),    QStringLiteral("staged"));
        QCOMPARE(svc.statusForPath(abs(root, QStringLiteral("ignored.txt"))),   QStringLiteral("ignored"));
        // A clean tracked file carries no status.
        QCOMPARE(svc.statusForPath(abs(root, QStringLiteral(".gitignore"))),    QString());
    }
};

QTEST_MAIN(TestGitStatusService)
#include "tst_gitstatusservice.moc"
