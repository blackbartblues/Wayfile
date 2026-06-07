#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QStandardPaths>
#include <QDir>
#include <QCoreApplication>
#include <QDebug>
#include <QElapsedTimer>
#include <QLoggingCategory>
#include <QSurfaceFormat>
#include <QFont>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QFile>
#include <QQuickWindow>
#include <QSaveFile>
#include <QTimer>
#include <QFontDatabase>
#include <QStyleHints>
#include <QFileInfo>
#include <QLocalServer>
#include <QLocalSocket>
#include <unistd.h>
#ifdef WAYFILE_HAS_KWINDOWSYSTEM
#include <KWindowEffects>
#endif

#include "services/configmanager.h"
#include "services/themeloader.h"
#include "services/fileoperations.h"
#include "services/clipboardmanager.h"
#include "services/draghelper.h"
#include "models/filesystemmodel.h"
#include "models/panestate.h"  // kMaxPanes
#include "models/tablistmodel.h"
#include "models/bookmarkmodel.h"
#include "models/devicemodel.h"
#include "models/recentfilesmodel.h"
#include "models/searchresultsmodel.h"
#include "models/searchproxymodel.h"
#include "models/dirfilterproxymodel.h"
#include "services/searchservice.h"
#include "services/undomanager.h"
#include "services/previewservice.h"
#include "services/metadataextractor.h"
#include "services/diskusageservice.h"
#include "services/remoteaccessservice.h"
#include "services/paneservices.h"
#include "services/runtimefeaturesservice.h"
#include "services/dependencychecker.h"
#include "services/gitstatusservice.h"
#include "providers/thumbnailprovider.h"
#include "providers/iconprovider.h"
#include "providers/pdfpreviewprovider.h"
#include <QIcon>
#include <QUrl>

int main(int argc, char *argv[])
{
    // Suppress noisy warnings:
    //   - qt.qpa.services: harmless portal registration warning on non-sandboxed apps
    //   - qt.svg: Qt's SVG parser complains about unsupported filter elements
    //     (feTurbulence, feColorMatrix, etc.) on every draw when such SVGs
    //     are previewed/thumbnailed, even though the file still renders.
    QLoggingCategory::setFilterRules(
        "qt.qpa.services.warning=false\n"
        "qt.svg.warning=false");

    // Keep the default path fast. Full-window MSAA is expensive on many
    // Wayland/compositor stacks; opt in with WAYFILE_MSAA=2/4 if wanted.
    QSurfaceFormat fmt;
    fmt.setSamples(qMax(0, qEnvironmentVariableIntValue("WAYFILE_MSAA")));
    QSurfaceFormat::setDefaultFormat(fmt);

    // Wayfile is a Wayland-only application (wl-copy clipboard, Hyprland
    // integration, KWin blur effects). Detect a non-Wayland session before
    // Qt tries to load the wayland QPA plugin so users see an actionable
    // message instead of the cryptic "Failed to create wl_display" error.
    if (qEnvironmentVariableIsEmpty("WAYLAND_DISPLAY")) {
        const QByteArray sessionType = qgetenv("XDG_SESSION_TYPE");
        const char *session = sessionType.isEmpty() ? "unknown" : sessionType.constData();
        fprintf(stderr,
                "\n"
                "Wayfile: no Wayland display available (XDG_SESSION_TYPE=%s).\n"
                "\n"
                "Wayfile only supports Wayland sessions. Your current session\n"
                "appears to be X11 or does not expose $WAYLAND_DISPLAY.\n"
                "\n"
                "To run Wayfile:\n"
                "  * Log out and pick a Wayland session at the login screen\n"
                "    (e.g. Hyprland, Niri, Sway, GNOME on Wayland, KDE Plasma Wayland).\n"
                "\n",
                session);
        return 1;
    }

    // Extract an optional path argument. We skip flag-style args so Qt's
    // own options (e.g. `-style`, `-qmljsdebugger`) don't get mistaken
    // for a path. Relative paths are resolved against the caller's cwd
    // before the single-instance handoff, so the receiving process sees
    // an absolute path regardless of where the launcher invoked us from.
    QString initialOpenPath;
    for (int i = 1; i < argc; ++i) {
        QString a = QString::fromLocal8Bit(argv[i]);
        if (a.startsWith('-')) continue;
        initialOpenPath = a;
        break;
    }
    if (!initialOpenPath.isEmpty()) {
        QFileInfo fi(initialOpenPath);
        if (fi.exists())
            initialOpenPath = fi.absoluteFilePath();
    }

    QGuiApplication app(argc, argv);
    app.setApplicationName("Wayfile");
    app.setOrganizationName("Wayfile");
    app.setDesktopFileName("io.github.blackbartblues.Wayfile");
    // Window icon (task switchers, server-side decorations). Bundled via qrc so
    // it resolves without depending on an installed theme icon.
    app.setWindowIcon(QIcon(QStringLiteral(":/assets/wayfile-logo.png")));

    // Startup timing: opt-in via WAYFILE_TIMING=1 so normal runs stay quiet.
    // Prints milliseconds from QGuiApplication construction at each phase.
    const bool timingEnabled = qEnvironmentVariableIntValue("WAYFILE_TIMING") != 0;
    QElapsedTimer startupTimer;
    startupTimer.start();
    auto mark = [&](const char *label) {
        if (timingEnabled)
            qDebug().nospace() << "[startup] " << qSetFieldWidth(6) << startupTimer.elapsed()
                               << qSetFieldWidth(0) << " ms  " << label;
    };
    mark("QGuiApplication ready");

    // Single-instance: if another Wayfile is already running for this user,
    // forward our arg over a per-uid unix domain socket and exit. The
    // running instance spawns a new tab for the path. Mirrors how browsers
    // handle `firefox <url>` when a window is already open.
    const QString wayfileSocketName = QStringLiteral("wayfile-%1").arg(static_cast<uint>(getuid()));
    {
        QLocalSocket probe;
        probe.connectToServer(wayfileSocketName);
        if (probe.waitForConnected(150)) {
            QJsonObject msg;
            if (!initialOpenPath.isEmpty())
                msg.insert(QStringLiteral("path"), initialOpenPath);
            QByteArray payload = QJsonDocument(msg).toJson(QJsonDocument::Compact);
            payload.append('\n');
            probe.write(payload);
            probe.waitForBytesWritten(500);
            probe.disconnectFromServer();
            return 0;
        }
    }

    QQuickStyle::setStyle("Basic");

    // Use native text rendering (FreeType/fontconfig) for crisp fonts matching GTK apps
    QQuickWindow::setTextRenderType(QQuickWindow::NativeTextRendering);

    auto resolveUiFont = [&](const QString &preferredFamily) {
        // Resolve the platform UI font first so the app does not depend on
        // theme-local font defaults that may not exist inside a sandbox.
        QFont font = QFontDatabase::systemFont(QFontDatabase::GeneralFont);
        if (font.family().isEmpty())
            font = app.font();

        if (!preferredFamily.trimmed().isEmpty())
            font.setFamily(preferredFamily.trimmed());

        font.setHintingPreference(QFont::PreferFullHinting);
        return font;
    };

    // Ensure config directory exists
    // User-visible config lives at ~/.config/wayfile. The CMake install-time
    // data dir macros (WAYFILE_DATA_DIR, WAYFILE_SOURCE_DIR) are rebuild-time
    // paths for finding shipped themes and QML, not user config.
    const QString configDir = QStandardPaths::writableLocation(QStandardPaths::HomeLocation)
                              + "/.config/wayfile";
    QDir().mkpath(configDir);
    const QString configPath = configDir + "/config.toml";

    auto firstExistingDir = [](const QStringList &paths) {
        for (const QString &path : paths) {
            const QString cleanPath = QDir::cleanPath(path);
            if (QDir(cleanPath).exists())
                return cleanPath;
        }
        return QString();
    };

    const QString appDir = QCoreApplication::applicationDirPath();
    const QString dataDir = firstExistingDir({
        QDir(appDir).filePath("../share/wayfile"),
        QDir(appDir).filePath("../../share/wayfile"),
        QStringLiteral(WAYFILE_DATA_DIR),
        QStringLiteral(WAYFILE_SOURCE_DIR),
    });

    QStringList themeSearchPaths = {
        QDir(appDir).filePath("../themes"),
        QDir(appDir).filePath("../../themes"),
        QStringLiteral(WAYFILE_DATA_DIR) + "/themes",
        QStringLiteral(WAYFILE_SOURCE_DIR) + "/themes",
    };
    if (!dataDir.isEmpty())
        themeSearchPaths.prepend(QDir(dataDir).filePath("themes"));

    const QString themesDir = firstExistingDir(themeSearchPaths);
    if (dataDir.isEmpty())
        qWarning() << "Wayfile: unable to locate data directory";
    if (themesDir.isEmpty())
        qWarning() << "Wayfile: unable to locate themes directory";

    // Wayfile fork: Bifröst is the signature theme. There's no Bifröst-light
    // variant yet, so we ignore the system colorScheme hint on first launch
    // and always seed bifrost. Once a light Bifröst token set ships, restore
    // the colorScheme-aware branch and pick between bifrost / bifrost-light.
    const QString systemDefaultTheme = QStringLiteral("bifrost");

    // Create backend instances
    ConfigManager *config = new ConfigManager(configPath, &app, themesDir, systemDefaultTheme);
    mark("ConfigManager loaded");
    app.setFont(resolveUiFont(config->fontFamily()));
    ThemeLoader *theme = new ThemeLoader(&app);
    theme->loadTheme(config->theme(), themesDir);
    mark("ThemeLoader loaded");

    TabListModel *tabModel = new TabListModel(&app);

    // Restore session (tabs + window geometry)
    const QString sessionPath = configDir + "/session.json";
    QJsonObject sessionData;
    {
        QFile sf(sessionPath);
        if (sf.open(QIODevice::ReadOnly)) {
            QJsonParseError parseError;
            const QJsonDocument doc = QJsonDocument::fromJson(sf.readAll(), &parseError);
            if (parseError.error == QJsonParseError::NoError && doc.isObject())
                sessionData = doc.object();
        }
    }
    if (sessionData.contains("tabs"))
        tabModel->restoreSession(sessionData.value("tabs").toArray(),
                                 sessionData.value("activeTab").toInt(0));

    BookmarkModel *bookmarks = new BookmarkModel(&app);
    bookmarks->setBookmarks(config->bookmarks());

    // Persist bookmark changes to config
    QObject::connect(bookmarks, &BookmarkModel::bookmarksChanged, [=]() {
        config->saveBookmarks(bookmarks->paths());
    });

    FileOperations *fileOps = new FileOperations(&app);
    UndoManager *undoManager = new UndoManager(fileOps, &app);
    ClipboardManager *clipboard = new ClipboardManager(&app);
    // DragHelper created after IconProvider below

    const QString homePath = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
    const QString initialPrimaryPath = tabModel->activeTab() && !tabModel->activeTab()->currentPath().isEmpty()
        ? tabModel->activeTab()->currentPath()
        : homePath;

    // Phase 1 M5: backend services bundled per pane so adding panes (Phase 2)
    // is a list append rather than a search-and-replace across main.cpp.  N
    // is hardcoded to 2 today; future code calls makePaneServices(idx) in a
    // loop.  Phase 2 P2-M6: the PaneServices struct now lives in a header
    // (services/paneservices.h) alongside PaneServicesProvider so QML can
    // reach slot idx 2 / 3 by index, not just slots 0 / 1 by name.

    auto makePaneServices = [&](int idx, const QString &initialPath, bool seedRoot) {
        PaneServices s;
        s.fsModel = new FileSystemModel(&app);
        s.fsModel->setShowHidden(config->showHidden());
        if (seedRoot)
            s.fsModel->setRootPath(initialPath);

        s.searchResults = new SearchResultsModel(&app);
        s.searchProxy = new SearchProxyModel(&app);
        s.searchProxy->setSourceModel(s.searchResults);

        s.searchService = new SearchService(&app);
        // Slots 0 / 1 keep the historical names so any logging or QML lookup
        // that grew up around them still matches; slots 2..N use a numeric
        // tag so the merge supertab can tell them apart in logs.
        s.searchService->setObjectName(idx == 0 ? QStringLiteral("primary")
                                       : idx == 1 ? QStringLiteral("secondary")
                                                  : QStringLiteral("pane%1").arg(idx));
        s.searchService->setResultsModel(s.searchResults);

        s.gitService = new GitStatusService(&app);
        s.fsModel->setGitStatusService(s.gitService);
        return s;
    };

    // Phase 2 P2-M3: pre-allocate the full pane services array up to the
    // kMaxPanes ceiling so the merge action doesn't need to grow the list at
    // runtime.  Only slot 0 gets a seeded root path up front; every other
    // slot sits on the user's home directory with no root applied until QML
    // points a live pane at it (onActiveIndexChanged / onCompleted / restore).
    QList<PaneServices> paneServices;
    for (int i = 0; i < kMaxPanes; ++i) {
        const QString seedPath = (i == 0) ? initialPrimaryPath : homePath;
        const bool seedRoot = (i == 0);
        paneServices.append(makePaneServices(i, seedPath, seedRoot));
    }
    mark("Pane services populated");

    // Miller view uses its own shared FileSystemModels (parent + preview
    // columns).  These are NOT per-pane — they're per-miller-instance — so
    // they stay outside the paneServices list.
    FileSystemModel *millerParentModel = new FileSystemModel(&app);
    millerParentModel->setShowHidden(config->showHidden());

    FileSystemModel *millerPreviewModel = new FileSystemModel(&app);
    millerPreviewModel->setShowHidden(config->showHidden());

    // Hidden view (#8 pkt5): a dedicated model rooted at Home that lists only
    // top-level dotfiles/dotfolders. Reusing FileSystemModel gives icons, git
    // status, previews and sorting for free; the sidebar "Hidden" entry flips
    // the active pane onto this model the same way "Recents" does. It always
    // shows hidden entries, so it is intentionally NOT wired to the
    // config.showHidden toggle below.
    FileSystemModel *hiddenEntries = new FileSystemModel(&app);
    hiddenEntries->setShowHidden(true);
    hiddenEntries->setHiddenOnly(true);
    hiddenEntries->setRootPath(QDir::homePath());

    PreviewService *previewService = new PreviewService(&app);
    MetadataExtractor *metadataExtractor = new MetadataExtractor(&app);
    DiskUsageService *diskUsageService = new DiskUsageService(&app);
    RemoteAccessService *remoteAccessService = new RemoteAccessService(&app);
    RuntimeFeaturesService *runtimeFeatures = new RuntimeFeaturesService(&app);
    config->setShowWindowControlsDefault(runtimeFeatures->useIntegratedWindowControls());

    // Keep the live UI in sync with persisted config values.
    QObject::connect(config, &ConfigManager::configChanged, [=, &app, &resolveUiFont]() {
        theme->loadTheme(config->theme() == QStringLiteral("custom")
                             ? config->customThemePath()
                             : config->theme(),
                         themesDir);
        bookmarks->setBookmarks(config->bookmarks());
        for (const PaneServices &s : paneServices)
            s.fsModel->setShowHidden(config->showHidden());
        millerParentModel->setShowHidden(config->showHidden());
        millerPreviewModel->setShowHidden(config->showHidden());
        app.setFont(resolveUiFont(config->fontFamily()));
    });

    // Connect lastWindowClosed to quit
    QObject::connect(&app, &QGuiApplication::lastWindowClosed, &app, &QGuiApplication::quit);

    // Create RecentFilesModel
    RecentFilesModel *recentFiles = new RecentFilesModel(configDir + "/recents.json", &app);

    // Create DeviceModel
    DeviceModel *devices = new DeviceModel(&app, true);

    // Aggregate runtime tools + compile-time features + DBus services for the
    // in-app MissingDependenciesDialog. Replaces the older hand-rolled
    // `which` loop that only logged to stderr.
    DependencyChecker *dependencies = new DependencyChecker(&app);

    // When the user installs a missing tool and clicks "Re-check", propagate
    // the refresh into feature services so their Q_PROPERTY bindings (e.g.
    // pdfPreviewAvailable) re-evaluate without requiring an app restart.
    QObject::connect(dependencies, &DependencyChecker::dependenciesChanged,
                     previewService, &PreviewService::refreshSupport);
    QObject::connect(dependencies, &DependencyChecker::dependenciesChanged,
                     metadataExtractor, &MetadataExtractor::refreshSupport);

    QQmlApplicationEngine engine;

    // Prefer the installed data layout, but keep source-tree fallbacks for dev builds.
    if (!dataDir.isEmpty()) {
        engine.addImportPath(dataDir);                           // Wayfile module
        engine.addImportPath(QDir(dataDir).filePath("src/qml")); // Quill module
    }
    engine.addImportPath(QStringLiteral(WAYFILE_DATA_DIR));
    engine.addImportPath(QStringLiteral(WAYFILE_DATA_DIR "/src/qml"));
    engine.addImportPath(QStringLiteral(WAYFILE_SOURCE_DIR));
    engine.addImportPath(QStringLiteral(WAYFILE_SOURCE_DIR "/src/qml"));

    // Set icon theme so QIcon::fromTheme() works (e.g. for drag pixmaps)
    QIcon::setThemeName(config->iconTheme());

    // Register image providers (keep pointer to IconProvider for DragHelper)
    auto *iconProvider = new IconProvider(config->iconTheme());
    engine.addImageProvider("thumbnail", new ThumbnailProvider);
    engine.addImageProvider("icon", iconProvider);
    engine.addImageProvider("pdfpreview", new PdfPreviewProvider);

    DragHelper *dragHelper = new DragHelper(iconProvider, &app);

    QObject::connect(config, &ConfigManager::configChanged, [=]() {
        QIcon::setThemeName(config->iconTheme());
        iconProvider->setPrimaryTheme(config->iconTheme());
    });

    // Creatable QML type: each HybridView instantiates its own folders/files
    // filter proxies over its pane's source model (Phase 8).
    qmlRegisterType<DirFilterProxyModel>("Wayfile", 1, 0, "DirFilterProxyModel");

    // Register context properties
    engine.rootContext()->setContextProperty("config", config);
    engine.rootContext()->setContextProperty("theme", theme);
    engine.rootContext()->setContextProperty("tabModel", tabModel);
    engine.rootContext()->setContextProperty("bookmarks", bookmarks);
    engine.rootContext()->setContextProperty("fileOps", fileOps);
    engine.rootContext()->setContextProperty("undoManager", undoManager);
    engine.rootContext()->setContextProperty("clipboard", clipboard);
    engine.rootContext()->setContextProperty("dragHelper", dragHelper);
    // Panes are addressed by index through paneServicesProvider (the N-pane
    // Repeater + every per-pane helper). Slot 0 also stays reachable under the
    // historical name "fsModel" for the many primary-pane call sites that grew
    // up around it; the old "splitFsModel" alias for slot 1 is gone with the
    // legacy split-view system (QML reaches slot 1+ via fsModelAt(i)).
    PaneServicesProvider *paneServicesProvider = new PaneServicesProvider(&app);
    paneServicesProvider->setServices(paneServices);
    engine.rootContext()->setContextProperty("paneServicesProvider", paneServicesProvider);

    engine.rootContext()->setContextProperty("fsModel", paneServices[0].fsModel);
    engine.rootContext()->setContextProperty("millerParentModel", millerParentModel);
    engine.rootContext()->setContextProperty("millerPreviewModel", millerPreviewModel);
    engine.rootContext()->setContextProperty("devices", devices);
    engine.rootContext()->setContextProperty("recentFiles", recentFiles);
    engine.rootContext()->setContextProperty("hiddenEntries", hiddenEntries);
    engine.rootContext()->setContextProperty("searchProxy", paneServices[0].searchProxy);
    engine.rootContext()->setContextProperty("searchResults", paneServices[0].searchResults);
    engine.rootContext()->setContextProperty("searchService", paneServices[0].searchService);
    engine.rootContext()->setContextProperty("splitSearchProxy", paneServices[1].searchProxy);
    engine.rootContext()->setContextProperty("splitSearchResults", paneServices[1].searchResults);
    engine.rootContext()->setContextProperty("splitSearchService", paneServices[1].searchService);
    engine.rootContext()->setContextProperty("previewService", previewService);
    engine.rootContext()->setContextProperty("metadataExtractor", metadataExtractor);
    engine.rootContext()->setContextProperty("diskUsageService", diskUsageService);
    engine.rootContext()->setContextProperty("remoteAccessService", remoteAccessService);
    engine.rootContext()->setContextProperty("runtimeFeatures", runtimeFeatures);
    engine.rootContext()->setContextProperty("dependencies", dependencies);

    const QString installedMainQml = dataDir.isEmpty()
        ? QString()
        : QDir(dataDir).filePath(QStringLiteral("Wayfile/qml/Main.qml"));

    // Prefer the installed on-disk module when it exists so deployed bundles
    // keep working even if Qt's embedded qrc payload is incomplete.
    mark("engine.load start");
    if (!installedMainQml.isEmpty() && QFile::exists(installedMainQml)) {
        engine.load(QUrl::fromLocalFile(installedMainQml));
    } else {
        engine.loadFromModule("Wayfile", "Main");
    }
    mark("engine.load done");

    if (engine.rootObjects().isEmpty())
        return -1;

    // First-frame checkpoint: one-shot hook on the root window's
    // frameSwapped signal so we know when the compositor has painted us.
    if (timingEnabled) {
        if (auto *win = qobject_cast<QQuickWindow *>(engine.rootObjects().first())) {
            auto *conn = new QMetaObject::Connection;
            *conn = QObject::connect(win, &QQuickWindow::frameSwapped, win, [conn, mark]() {
                mark("first frame swapped");
                QObject::disconnect(*conn);
                delete conn;
            }, Qt::QueuedConnection);
        }
    }

    auto applyWindowEffects = [config](QQuickWindow *window) {
        if (!window)
            return;

#ifdef WAYFILE_HAS_KWINDOWSYSTEM
        // KWin blur only shows through translucent content; Hyprland keeps
        // using compositor rules against the same transparent window surface.
        const bool blurRequested = config->transparencyEnabled();
        const bool blurAvailable = KWindowEffects::isEffectAvailable(KWindowEffects::BlurBehind);
        KWindowEffects::enableBlurBehind(window, blurRequested && blurAvailable);

        const bool contrastAvailable = KWindowEffects::isEffectAvailable(KWindowEffects::BackgroundContrast);
        KWindowEffects::enableBackgroundContrast(window, blurRequested && contrastAvailable);
#else
        Q_UNUSED(window)
#endif
    };

    QTimer sessionSaveTimer;
    sessionSaveTimer.setSingleShot(true);
    sessionSaveTimer.setInterval(250);

    auto saveSession = [&]() {
        QJsonObject session;
        session["tabs"] = tabModel->saveSession();
        session["activeTab"] = tabModel->activeIndex();

        if (auto *win = !engine.rootObjects().isEmpty()
                ? qobject_cast<QQuickWindow *>(engine.rootObjects().first())
                : nullptr) {
            session["windowX"] = win->x();
            session["windowY"] = win->y();
            session["windowWidth"] = win->width();
            session["windowHeight"] = win->height();

            QWindow::Visibility savedVisibility = win->visibility();
            if (savedVisibility == QWindow::Hidden
                    || savedVisibility == QWindow::AutomaticVisibility
                    || savedVisibility == QWindow::Minimized) {
                savedVisibility = QWindow::Windowed;
            }
            session["windowVisibility"] = static_cast<int>(savedVisibility);
        }

        QSaveFile sf(sessionPath);
        if (sf.open(QIODevice::WriteOnly)) {
            sf.write(QJsonDocument(session).toJson(QJsonDocument::Compact));
            sf.commit();
        }
    };

    auto scheduleSessionSave = [&]() {
        sessionSaveTimer.start();
    };

    QObject::connect(&sessionSaveTimer, &QTimer::timeout, &app, saveSession);
    QObject::connect(tabModel, &TabListModel::sessionChanged, &app, scheduleSessionSave);

    if (auto *win = qobject_cast<QQuickWindow *>(engine.rootObjects().first())) {
        applyWindowEffects(win);
        QObject::connect(config, &ConfigManager::configChanged, win, [=]() {
            applyWindowEffects(win);
        });
        QObject::connect(win, &QQuickWindow::xChanged, &app, scheduleSessionSave);
        QObject::connect(win, &QQuickWindow::yChanged, &app, scheduleSessionSave);
        QObject::connect(win, &QQuickWindow::widthChanged, &app, scheduleSessionSave);
        QObject::connect(win, &QQuickWindow::heightChanged, &app, scheduleSessionSave);
        QObject::connect(win, &QQuickWindow::visibilityChanged, &app, scheduleSessionSave);
    }

    // Save session on quit
    QObject::connect(&app, &QCoreApplication::aboutToQuit, [&]() {
        sessionSaveTimer.stop();
        saveSession();
    });

    // Restore window geometry
    if (sessionData.contains("windowWidth") && !engine.rootObjects().isEmpty()) {
        if (auto *win = qobject_cast<QQuickWindow *>(engine.rootObjects().first())) {
            win->setX(sessionData.value("windowX").toInt());
            win->setY(sessionData.value("windowY").toInt());
            win->setWidth(sessionData.value("windowWidth").toInt());
            win->setHeight(sessionData.value("windowHeight").toInt());

            QWindow::Visibility restoredVisibility = QWindow::Windowed;
            if (sessionData.contains("windowVisibility")) {
                restoredVisibility = static_cast<QWindow::Visibility>(
                    sessionData.value("windowVisibility").toInt());
            }

            if (restoredVisibility == QWindow::Maximized
                    || restoredVisibility == QWindow::FullScreen
                    || restoredVisibility == QWindow::Windowed) {
                win->setVisibility(restoredVisibility);
            } else {
                win->showNormal();
            }
        }
    }

    // Raise, focus, and navigate to a path — used for both the initial
    // argv path and for paths forwarded by a subsequent invocation over
    // the single-instance socket. Empty path just raises the window.
    auto openPathInNewTab = [&engine, tabModel](const QString &path) {
        if (!path.isEmpty()) {
            tabModel->addTab();
            if (auto *tab = tabModel->activeTab())
                tab->navigateTo(path);
        }
        if (engine.rootObjects().isEmpty())
            return;
        if (auto *win = qobject_cast<QQuickWindow *>(engine.rootObjects().first())) {
            if (win->visibility() == QWindow::Minimized || win->visibility() == QWindow::Hidden)
                win->showNormal();
            win->raise();
            win->requestActivate();
        }
    };

    // Stale socket from a crashed previous instance would block listen().
    QLocalServer::removeServer(wayfileSocketName);
    QLocalServer *ipcServer = new QLocalServer(&app);
    ipcServer->setSocketOptions(QLocalServer::UserAccessOption);
    if (!ipcServer->listen(wayfileSocketName)) {
        qWarning() << "Wayfile: single-instance IPC listen failed:" << ipcServer->errorString();
    }
    QObject::connect(ipcServer, &QLocalServer::newConnection, &app, [ipcServer, openPathInNewTab]() {
        while (QLocalSocket *conn = ipcServer->nextPendingConnection()) {
            QObject::connect(conn, &QLocalSocket::readyRead, conn, [conn, openPathInNewTab]() {
                const QByteArray data = conn->readAll();
                for (const QByteArray &line : data.split('\n')) {
                    const QByteArray trimmed = line.trimmed();
                    if (trimmed.isEmpty()) continue;
                    QJsonParseError err;
                    const QJsonDocument doc = QJsonDocument::fromJson(trimmed, &err);
                    if (err.error != QJsonParseError::NoError || !doc.isObject()) continue;
                    openPathInNewTab(doc.object().value(QStringLiteral("path")).toString());
                }
            });
            QObject::connect(conn, &QLocalSocket::disconnected, conn, &QObject::deleteLater);
        }
    });

    // Apply the path this process was launched with (if any) as a new tab
    // on the restored session.
    if (!initialOpenPath.isEmpty())
        QTimer::singleShot(0, &app, [=]() { openPathInNewTab(initialOpenPath); });

    return app.exec();
}
