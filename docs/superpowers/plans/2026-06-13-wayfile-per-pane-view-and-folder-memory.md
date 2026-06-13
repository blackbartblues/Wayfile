# Per-pane View + Per-folder View Memory — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each split pane its own independent view mode, and let folders remember their last-used view (setting-gated, default ON), persisting both across restarts.

**Architecture:** `TabModel` already stores `viewMode` per pane (`PaneState`); we drop the mirror loop that forced panes equal and add a pane-indexed setter. A new standalone `FolderViewStore` (JSON file, `RecentFilesModel` pattern) holds path→viewMode with an LRU cap, gated by a new `ConfigManager.rememberFolderView` flag. QML rebinds every view read/write from tab-level to the focused pane and applies/records folder views on navigation and view-switch.

**Tech Stack:** Qt6/C++ (QObject, QJsonDocument, toml++), QML, CTest + Qt6::Test.

**Spec:** `docs/superpowers/specs/2026-06-13-wayfile-per-pane-view-and-folder-memory-design.md`

---

## File Structure

**Backend (C++):**
- `src/models/tabmodel.{h,cpp}` — drop mirror loop; add `setPaneViewMode(idx,mode)` + `paneViewModeChanged(idx)`.
- `src/models/tablistmodel.{h,cpp}` — per-pane session schema; per-pane reopen-closed; new signal connection.
- `src/models/folderviewstore.{h,cpp}` — **NEW** path→viewMode JSON store.
- `src/services/configmanager.{h,cpp}` — `rememberFolderView` flag.
- `src/main.cpp` — construct + expose `folderViewStore`.
- `src/CMakeLists.txt`, `tests/CMakeLists.txt` — register new source + test.

**Frontend (QML):**
- `src/qml/Main.qml` — `paneViewModes` mirror, helpers, pane-indexed bindings, nav hooks.
- `src/qml/components/AppShortcuts.qml`, `src/qml/components/MainOverlays.qml` — route view-switch to focused pane.
- `src/qml/components/SettingsPanel.qml`, `src/qml/components/SettingsSectionLayout.qml` — the toggle.

**Tests:**
- `tests/tst_folderviewstore.cpp` — **NEW**.
- `tests/tst_tabmodel.cpp` — extend (per-pane setter + session round-trip; this target links both `tabmodel.cpp` and `tablistmodel.cpp`).
- `tests/tst_configmanager.cpp` — extend (flag default + round-trip).

**Build order:** Task 1 → 2 (backend state) → 3 (store) → 4 (config) → 5 (wiring) → 6 → 7 → 8 (QML) → 9 (verify). Each backend task is independently testable; QML tasks build + smoke.

---

## Task 1: TabModel — independent per-pane view

**Files:**
- Modify: `src/models/tabmodel.h` (add method + signal)
- Modify: `src/models/tabmodel.cpp:114-124` (drop mirror loop), add `setPaneViewMode`
- Test: `tests/tst_tabmodel.cpp`

- [ ] **Step 1: Write the failing tests**

In `tests/tst_tabmodel.cpp`, add these slots inside the `private slots:` section (e.g. after `testSupertabPaneState()` near line 69):

```cpp
    void testSetViewModeNoLongerMirrors()
    {
        TabModel tab;                       // pane 0 starts "hybrid"
        tab.addPane("/tmp");                // pane 1 inherits "hybrid"
        tab.setViewMode("grid");            // sets pane 0 only now
        QCOMPARE(tab.paneViewMode(0), QString("grid"));
        QCOMPARE(tab.paneViewMode(1), QString("hybrid"));   // NOT mirrored
    }

    void testSetPaneViewModeIndependent()
    {
        TabModel tab;
        tab.addPane("/tmp");
        tab.setPaneViewMode(1, "detailed");
        QCOMPARE(tab.paneViewMode(0), QString("hybrid"));
        QCOMPARE(tab.paneViewMode(1), QString("detailed"));
    }

    void testSetPaneViewModeSignal()
    {
        TabModel tab;
        QSignalSpy spy(&tab, &TabModel::paneViewModeChanged);
        tab.setPaneViewMode(0, "miller");
        QCOMPARE(spy.count(), 1);
        QCOMPARE(spy.at(0).at(0).toInt(), 0);
        // idx 0 also pulses the tab-level signal for session/back-compat readers.
        QSignalSpy tabSpy(&tab, &TabModel::viewModeChanged);
        tab.setPaneViewMode(0, "grid");
        QCOMPARE(tabSpy.count(), 1);
    }

    void testSetPaneViewModeOutOfRangeNoop()
    {
        TabModel tab;
        QSignalSpy spy(&tab, &TabModel::paneViewModeChanged);
        tab.setPaneViewMode(5, "grid");     // no pane 5
        tab.setPaneViewMode(-1, "grid");
        QCOMPARE(spy.count(), 0);
        QCOMPARE(tab.paneViewMode(0), QString("hybrid"));
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cmake -B build && cmake --build build -j --target tst_tabmodel && ctest --test-dir build -R tst_tabmodel --output-on-failure`
Expected: FAIL — `setPaneViewMode` is not a member of `TabModel`, `paneViewModeChanged` undefined (compile error).

- [ ] **Step 3: Add the declaration + signal to the header**

In `src/models/tabmodel.h`, after line 78 (`Q_INVOKABLE QString paneViewMode(int idx) const;`):

```cpp
    Q_INVOKABLE QString paneViewMode(int idx) const;
    // Set one pane's view mode without touching its siblings. idx 0 also emits
    // viewModeChanged() so tab-level consumers (session save, miller sync for
    // the primary pane) keep firing.
    Q_INVOKABLE void setPaneViewMode(int idx, const QString &mode);
```

In `src/models/tabmodel.h`, after line 114 (`void panePathChanged(int idx);`):

```cpp
    void panePathChanged(int idx);
    // Emitted when a single pane's view mode changes via setPaneViewMode.
    // Carries the pane index so Main.qml refreshes that pane's binding.
    void paneViewModeChanged(int idx);
```

- [ ] **Step 4: Drop the mirror loop and implement the setter**

In `src/models/tabmodel.cpp`, replace `setViewMode` (lines 114-124):

```cpp
void TabModel::setViewMode(const QString &mode)
{
    if (m_panes[0].viewMode == mode)
        return;
    m_panes[0].viewMode = mode;
    emit viewModeChanged();
}
```

Then add `setPaneViewMode` immediately after the `paneViewMode` getter (after line 362):

```cpp
void TabModel::setPaneViewMode(int idx, const QString &mode)
{
    if (idx < 0 || idx >= m_panes.size())
        return;
    if (m_panes[idx].viewMode == mode)
        return;
    m_panes[idx].viewMode = mode;
    emit paneViewModeChanged(idx);
    if (idx == 0)
        emit viewModeChanged();
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cmake --build build -j --target tst_tabmodel && ctest --test-dir build -R tst_tabmodel --output-on-failure`
Expected: PASS (all `testSetPaneViewMode*` + `testSetViewModeNoLongerMirrors`, and the pre-existing TabModel tests still green).

- [ ] **Step 6: Commit**

```bash
git add src/models/tabmodel.h src/models/tabmodel.cpp tests/tst_tabmodel.cpp
git commit -m "feat(view): per-pane view mode setter, drop tab-level mirror"
```

---

## Task 2: TabListModel — persist per-pane views

**Files:**
- Modify: `src/models/tablistmodel.h:133-140` (ClosedTabInfo struct)
- Modify: `src/models/tablistmodel.cpp` — `connectTab` (~90), `closeTab` (~195-205), `reopenClosedTab` (668-694), `saveSession` (696-715), `restoreSession` (717-755)
- Test: `tests/tst_tabmodel.cpp`

- [ ] **Step 1: Write the failing tests**

In `tests/tst_tabmodel.cpp`, add these slots in the `// === TabListModel tests ===` region (e.g. after the existing session round-trip test near line 426):

```cpp
    void testSessionPreservesPerPaneViews()
    {
        TabListModel model;
        TabModel *tab = model.activeTab();
        tab->navigateTo("/tmp");
        tab->addPane("/usr");
        tab->setSupertab(true);
        tab->setPaneViewMode(0, "grid");
        tab->setPaneViewMode(1, "detailed");

        const QJsonArray saved = model.saveSession();
        TabListModel restored;
        restored.restoreSession(saved, 0);

        TabModel *rt = restored.activeTab();
        QCOMPARE(rt->paneCount(), 2);
        QCOMPARE(rt->paneViewMode(0), QString("grid"));
        QCOMPARE(rt->paneViewMode(1), QString("detailed"));
    }

    void testLegacySessionStringPanesRestore()
    {
        // Sessions written before this feature stored panes as bare path
        // strings and a single top-level viewMode. They must still restore.
        QJsonObject legacy{
            {"path", "/tmp"},
            {"viewMode", "miller"},
            {"sortBy", "name"},
            {"sortAscending", true},
            {"panes", QJsonArray{QString("/tmp"), QString("/usr")}},
            {"isSupertab", true},
        };
        TabListModel model;
        model.restoreSession(QJsonArray{legacy}, 0);
        TabModel *tab = model.activeTab();
        QCOMPARE(tab->paneCount(), 2);
        QCOMPARE(tab->paneViewMode(0), QString("miller"));
        QCOMPARE(tab->paneViewMode(1), QString("miller"));   // legacy → shared
    }

    void testReopenClosedTabKeepsPerPaneViews()
    {
        TabListModel model;
        model.addTab();                       // a 2nd tab so close is allowed
        model.setActiveIndex(1);              // pin to the new tab deterministically
        TabModel *tab = model.activeTab();
        tab->navigateTo("/tmp");
        tab->addPane("/usr");
        tab->setSupertab(true);
        tab->setPaneViewMode(0, "grid");
        tab->setPaneViewMode(1, "detailed");

        model.closeTab(model.activeIndex());
        model.reopenClosedTab();

        TabModel *rt = model.activeTab();
        QCOMPARE(rt->paneCount(), 2);
        QCOMPARE(rt->paneViewMode(0), QString("grid"));
        QCOMPARE(rt->paneViewMode(1), QString("detailed"));
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cmake --build build -j --target tst_tabmodel && ctest --test-dir build -R tst_tabmodel --output-on-failure`
Expected: FAIL — restored/ reopened panes come back as `"hybrid"` (or the legacy single value) for pane 1 because per-pane views aren't persisted yet.

- [ ] **Step 3: Persist per-pane views in `saveSession`**

In `src/models/tablistmodel.cpp`, replace `saveSession` (lines 696-715):

```cpp
QJsonArray TabListModel::saveSession() const
{
    QJsonArray arr;
    for (const auto *tab : m_tabs) {
        // Persist each pane's path AND its independent view so merged
        // supertabs and per-pane views both survive a restart.
        QJsonArray panes;
        for (int i = 0; i < tab->paneCount(); ++i)
            panes.append(QJsonObject{
                {"path", tab->paneCurrentPath(i)},
                {"viewMode", tab->paneViewMode(i)},
            });

        arr.append(QJsonObject{
            {"path", tab->currentPath()},
            {"viewMode", tab->viewMode()},   // = pane 0; kept for older readers
            {"sortBy", tab->sortBy()},
            {"sortAscending", tab->sortAscending()},
            {"panes", panes},
            {"isSupertab", tab->isSupertab()},
        });
    }
    return arr;
}
```

- [ ] **Step 4: Read per-pane views (with legacy fallback) in `restoreSession`**

In `src/models/tablistmodel.cpp`, replace the block in `restoreSession` from line 730 to line 749 (from `const QJsonArray panes = ...` through the `if (isSupertab && panes.size() > 1) { ... }` block) with:

```cpp
        const QJsonArray panes = obj.value("panes").toArray();
        const bool isSupertab = obj.value("isSupertab").toBool(false);
        const QString legacyViewMode = obj.value("viewMode").toString("grid");

        // A pane element is either a bare path string (legacy session) or a
        // {path, viewMode} object (per-pane view persistence).
        auto panePathAt = [&](int i) -> QString {
            const QJsonValue v = panes.at(i);
            return v.isObject() ? v.toObject().value("path").toString() : v.toString();
        };
        auto paneViewAt = [&](int i) -> QString {
            const QJsonValue v = panes.at(i);
            return v.isObject() ? v.toObject().value("viewMode").toString(legacyViewMode)
                                : legacyViewMode;
        };

        // Pane 0 path: prefer the panes array, fall back to the legacy "path"
        // field for sessions written before merge persistence existed.
        const QString firstPath = panes.isEmpty()
            ? obj.value("path").toString()
            : panePathAt(0);
        tab->navigateTo(normalizedSessionPath(firstPath));
        tab->setViewMode(panes.isEmpty() ? legacyViewMode : paneViewAt(0));
        tab->setSortBy(obj.value("sortBy").toString("name"));
        tab->setSortAscending(obj.value("sortAscending").toBool(true));

        if (isSupertab && panes.size() > 1) {
            // Recreate the merged supertab: one pane per saved path, each with
            // its own restored view — mirrors mergeSelected().
            for (int i = 1; i < panes.size(); ++i) {
                tab->addPane(normalizedSessionPath(panePathAt(i)));
                tab->setPaneViewMode(i, paneViewAt(i));
            }
            tab->setSupertab(true);
        }
```

- [ ] **Step 5: Carry per-pane views through reopen-closed-tab**

In `src/models/tablistmodel.h`, add a field to `ClosedTabInfo` (after line 136, `QStringList panePaths;`):

```cpp
    struct ClosedTabInfo {
        QString path;
        QString viewMode;
        QStringList panePaths;
        QStringList paneViewModes;
        QString sortBy;
        bool sortAscending = true;
        bool isSupertab = false;
    };
```

In `src/models/tablistmodel.cpp`, in `closeTab`, replace the `panePaths` collection + `m_closedTabs.append({...})` (lines 195-205):

```cpp
    TabModel *tab = m_tabs.at(index);
    QStringList panePaths, paneViewModes;
    for (int i = 0; i < tab->paneCount(); ++i) {
        panePaths.append(tab->paneCurrentPath(i));
        paneViewModes.append(tab->paneViewMode(i));
    }
    m_closedTabs.append({
        tab->currentPath(),
        tab->viewMode(),
        panePaths,
        paneViewModes,
        tab->sortBy(),
        tab->sortAscending(),
        tab->isSupertab(),
    });
```

In `src/models/tablistmodel.cpp`, in `reopenClosedTab`, after the supertab restore block (after line 687, `tab->setSupertab(true);` / its closing `}`), add:

```cpp
    // Restore each pane's independent view (pane 0 already set via setViewMode).
    for (int i = 0; i < info.paneViewModes.size() && i < tab->paneCount(); ++i)
        tab->setPaneViewMode(i, info.paneViewModes.at(i));
```

- [ ] **Step 6: Mark the session dirty on per-pane view changes**

In `src/models/tablistmodel.cpp`, in `connectTab`, after line 90 (`connect(tab, &TabModel::viewModeChanged, this, &TabListModel::sessionChanged);`):

```cpp
    connect(tab, &TabModel::viewModeChanged, this, &TabListModel::sessionChanged);
    connect(tab, &TabModel::paneViewModeChanged, this, &TabListModel::sessionChanged);
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cmake --build build -j --target tst_tabmodel && ctest --test-dir build -R tst_tabmodel --output-on-failure`
Expected: PASS (new session/reopen tests + all pre-existing TabListModel tests).

- [ ] **Step 8: Commit**

```bash
git add src/models/tablistmodel.h src/models/tablistmodel.cpp tests/tst_tabmodel.cpp
git commit -m "feat(view): persist per-pane view modes across session + reopen"
```

---

## Task 3: FolderViewStore service

**Files:**
- Create: `src/models/folderviewstore.h`
- Create: `src/models/folderviewstore.cpp`
- Modify: `src/CMakeLists.txt:28` (add source)
- Create: `tests/tst_folderviewstore.cpp`
- Modify: `tests/CMakeLists.txt` (add test target)

- [ ] **Step 1: Write the failing test**

Create `tests/tst_folderviewstore.cpp`:

```cpp
#include <QTest>
#include <QTemporaryDir>
#include "models/folderviewstore.h"

class TestFolderViewStore : public QObject
{
    Q_OBJECT

private:
    QString storePath(const QTemporaryDir &dir) const
    {
        return dir.path() + "/folder-views.json";
    }

private slots:
    void testMissReturnsEmptyAndNoWrite()
    {
        QTemporaryDir dir;
        FolderViewStore store(storePath(dir));
        QCOMPARE(store.viewForFolder("/tmp"), QString());
        // A pure lookup must not create the file.
        QVERIFY(!QFile::exists(storePath(dir)));
    }

    void testRememberThenLookup()
    {
        QTemporaryDir dir;
        FolderViewStore store(storePath(dir));
        store.rememberView("/tmp/a", "grid");
        QCOMPARE(store.viewForFolder("/tmp/a"), QString("grid"));
    }

    void testTrailingSlashNormalized()
    {
        QTemporaryDir dir;
        FolderViewStore store(storePath(dir));
        store.rememberView("/tmp/a/", "detailed");
        QCOMPARE(store.viewForFolder("/tmp/a"), QString("detailed"));
        QCOMPARE(store.viewForFolder("/tmp/a/"), QString("detailed"));
    }

    void testUpdateOverwritesNotDuplicates()
    {
        QTemporaryDir dir;
        FolderViewStore store(storePath(dir));
        store.rememberView("/x", "grid");
        store.rememberView("/x", "miller");
        QCOMPARE(store.viewForFolder("/x"), QString("miller"));
        // Reload to confirm only one entry persisted.
        FolderViewStore reloaded(storePath(dir));
        QCOMPARE(reloaded.viewForFolder("/x"), QString("miller"));
    }

    void testBlankPathOrModeIgnored()
    {
        QTemporaryDir dir;
        FolderViewStore store(storePath(dir));
        store.rememberView("", "grid");
        store.rememberView("/y", "");
        QCOMPARE(store.viewForFolder("/y"), QString());
    }

    void testForgetAndClear()
    {
        QTemporaryDir dir;
        FolderViewStore store(storePath(dir));
        store.rememberView("/a", "grid");
        store.rememberView("/b", "miller");
        store.forget("/a");
        QCOMPARE(store.viewForFolder("/a"), QString());
        QCOMPARE(store.viewForFolder("/b"), QString("miller"));
        store.clear();
        QCOMPARE(store.viewForFolder("/b"), QString());
    }

    void testPersistAcrossInstances()
    {
        QTemporaryDir dir;
        {
            FolderViewStore store(storePath(dir));
            store.rememberView("/keep", "detailed");
        }
        FolderViewStore reopened(storePath(dir));
        QCOMPARE(reopened.viewForFolder("/keep"), QString("detailed"));
    }

    void testGarbageFileToleratedAsEmpty()
    {
        QTemporaryDir dir;
        QFile f(storePath(dir));
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("not json at all {[");
        f.close();
        FolderViewStore store(storePath(dir));   // must not crash
        QCOMPARE(store.viewForFolder("/anything"), QString());
        store.rememberView("/ok", "grid");       // and stays usable
        QCOMPARE(store.viewForFolder("/ok"), QString("grid"));
    }
};

QTEST_MAIN(TestFolderViewStore)
#include "tst_folderviewstore.moc"
```

- [ ] **Step 2: Register the test target (so it can compile + fail)**

In `src/CMakeLists.txt`, add after line 28 (`models/recentfilesmodel.cpp`):

```cmake
    models/recentfilesmodel.cpp
    models/folderviewstore.cpp
```

In `tests/CMakeLists.txt`, add after the `tst_bookmarkmodel` block (it links a single model + Qt6::Test/Core — same shape):

```cmake
add_executable(tst_folderviewstore tst_folderviewstore.cpp
    ${CMAKE_SOURCE_DIR}/src/models/folderviewstore.cpp
)
target_include_directories(tst_folderviewstore PRIVATE ${CMAKE_SOURCE_DIR}/src)
target_link_libraries(tst_folderviewstore PRIVATE Qt6::Test Qt6::Core)
add_test(NAME tst_folderviewstore COMMAND tst_folderviewstore)
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cmake -B build && cmake --build build -j --target tst_folderviewstore`
Expected: FAIL — `folderviewstore.h` does not exist (compile error).

- [ ] **Step 4: Write the header**

Create `src/models/folderviewstore.h`:

```cpp
#pragma once

#include <QObject>
#include <QString>
#include <QList>

// Path-keyed store of a folder's last user-chosen view mode. Mirrors the
// RecentFilesModel idiom: load() on construct, save() on every mutation, and an
// LRU cap so the file can't grow without bound. Plain QObject (never displayed);
// exposed to QML as the `folderViewStore` context property.
class FolderViewStore : public QObject
{
    Q_OBJECT

public:
    explicit FolderViewStore(const QString &storagePath, QObject *parent = nullptr);

    // "" when the folder has no remembered view (caller leaves the pane as-is).
    // Pure lookup: never reorders and never writes to disk.
    Q_INVOKABLE QString viewForFolder(const QString &path) const;
    // Records path -> mode, moving it to the front (LRU). A blank path or mode
    // is ignored.
    Q_INVOKABLE void rememberView(const QString &path, const QString &mode);
    Q_INVOKABLE void forget(const QString &path);
    Q_INVOKABLE void clear();

private:
    void load();
    void save() const;
    static QString normalize(const QString &path);

    struct Entry {
        QString path;
        QString viewMode;
    };

    QList<Entry> m_entries;   // most-recently-written at front
    QString m_storagePath;
    int m_maxEntries = 500;
};
```

- [ ] **Step 5: Write the implementation**

Create `src/models/folderviewstore.cpp`:

```cpp
#include "models/folderviewstore.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

FolderViewStore::FolderViewStore(const QString &storagePath, QObject *parent)
    : QObject(parent), m_storagePath(storagePath)
{
    load();
}

QString FolderViewStore::normalize(const QString &path)
{
    if (path.size() > 1 && path.endsWith('/'))
        return path.left(path.size() - 1);
    return path;
}

QString FolderViewStore::viewForFolder(const QString &path) const
{
    const QString key = normalize(path);
    for (const Entry &e : m_entries) {
        if (e.path == key)
            return e.viewMode;
    }
    return QString();
}

void FolderViewStore::rememberView(const QString &path, const QString &mode)
{
    const QString key = normalize(path);
    if (key.isEmpty() || mode.isEmpty())
        return;

    for (int i = 0; i < m_entries.size(); ++i) {
        if (m_entries[i].path == key) {
            if (i == 0 && m_entries[i].viewMode == mode)
                return;                 // already front + unchanged: skip write
            m_entries.removeAt(i);
            break;
        }
    }
    m_entries.prepend({key, mode});

    if (m_entries.size() > m_maxEntries)
        m_entries.resize(m_maxEntries);

    save();
}

void FolderViewStore::forget(const QString &path)
{
    const QString key = normalize(path);
    for (int i = 0; i < m_entries.size(); ++i) {
        if (m_entries[i].path == key) {
            m_entries.removeAt(i);
            save();
            return;
        }
    }
}

void FolderViewStore::clear()
{
    if (m_entries.isEmpty())
        return;
    m_entries.clear();
    save();
}

void FolderViewStore::load()
{
    QFile file(m_storagePath);
    if (!file.open(QIODevice::ReadOnly))
        return;

    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isArray())
        return;

    for (const auto &val : doc.array()) {
        const QJsonObject obj = val.toObject();
        const QString path = obj.value("path").toString();
        const QString mode = obj.value("viewMode").toString();
        if (!path.isEmpty() && !mode.isEmpty())
            m_entries.append({path, mode});
    }
    if (m_entries.size() > m_maxEntries)
        m_entries.resize(m_maxEntries);
}

void FolderViewStore::save() const
{
    QFile file(m_storagePath);
    if (!file.open(QIODevice::WriteOnly))
        return;

    QJsonArray arr;
    for (const Entry &e : m_entries) {
        arr.append(QJsonObject{
            {"path", e.path},
            {"viewMode", e.viewMode},
        });
    }
    file.write(QJsonDocument(arr).toJson(QJsonDocument::Compact));
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cmake -B build && cmake --build build -j --target tst_folderviewstore && ctest --test-dir build -R tst_folderviewstore --output-on-failure`
Expected: PASS (all 8 slots).

- [ ] **Step 7: Commit**

```bash
git add src/models/folderviewstore.h src/models/folderviewstore.cpp src/CMakeLists.txt tests/tst_folderviewstore.cpp tests/CMakeLists.txt
git commit -m "feat(view): FolderViewStore — path-keyed remembered view modes"
```

---

## Task 4: ConfigManager — `rememberFolderView` flag

**Files:**
- Modify: `src/services/configmanager.h:31,86,149` (property, getter, member)
- Modify: `src/services/configmanager.cpp` — defaults (~399), parse (~471), getter (~621), saveSettings (~761)
- Test: `tests/tst_configmanager.cpp`

- [ ] **Step 1: Write the failing tests**

In `tests/tst_configmanager.cpp`, add these slots in the `private slots:` section (match the file's existing temp-config pattern; if a test writes a config file, follow the surrounding tests' helper for the config path):

```cpp
    void testRememberFolderViewDefaultsTrue()
    {
        QTemporaryDir dir;
        ConfigManager config(dir.path() + "/config.toml");
        QCOMPARE(config.rememberFolderView(), true);
    }

    void testRememberFolderViewParsedFromToml()
    {
        QTemporaryDir dir;
        const QString path = dir.path() + "/config.toml";
        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("[general]\nremember_folder_view = false\n");
        f.close();
        ConfigManager config(path);
        QCOMPARE(config.rememberFolderView(), false);
    }

    void testRememberFolderViewRoundTrip()
    {
        QTemporaryDir dir;
        const QString path = dir.path() + "/config.toml";
        ConfigManager config(path);
        config.saveSettings(QVariantMap{{"rememberFolderView", false}});
        QCOMPARE(config.rememberFolderView(), false);
        ConfigManager reloaded(path);
        QCOMPARE(reloaded.rememberFolderView(), false);
    }
```

> If `tst_configmanager.cpp` does not already `#include <QTemporaryDir>`, add it near the top includes.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cmake --build build -j --target tst_configmanager && ctest --test-dir build -R "tst_configmanager$" --output-on-failure`
Expected: FAIL — `rememberFolderView` is not a member of `ConfigManager` (compile error).

- [ ] **Step 3: Add property, getter declaration, and member to the header**

In `src/services/configmanager.h`, after line 31 (`Q_PROPERTY(int gridCellSize ...)`):

```cpp
    Q_PROPERTY(int gridCellSize READ gridCellSize NOTIFY configChanged)
    Q_PROPERTY(bool rememberFolderView READ rememberFolderView NOTIFY configChanged)
```

After line 86 (`int gridCellSize() const;`):

```cpp
    int gridCellSize() const;
    bool rememberFolderView() const;
```

After line 149 (`int m_gridCellSize;`):

```cpp
    int m_gridCellSize;
    bool m_rememberFolderView = true;
```

- [ ] **Step 4: Default, parse, getter, and save in the cpp**

In `src/services/configmanager.cpp`, in `setDefaults()` after line 399 (`m_gridCellSize = 180; ...`):

```cpp
    m_gridCellSize = 180;  // keep in sync with FileGridView min/maxCellSize (110–320)
    m_rememberFolderView = true;
```

In `loadConfig()` after line 471 (the `grid_cell_size` parse):

```cpp
        if (auto v = config["general"]["grid_cell_size"].value<int64_t>())
            m_gridCellSize = qBound(110, static_cast<int>(*v), 320);
        if (auto v = config["general"]["remember_folder_view"].value<bool>())
            m_rememberFolderView = *v;
```

Add the getter after line 621 (`int ConfigManager::gridCellSize() const ...`):

```cpp
int ConfigManager::gridCellSize() const { return m_gridCellSize; }
bool ConfigManager::rememberFolderView() const { return m_rememberFolderView; }
```

In `saveSettings()` after the `gridCellSize` block (after line 761):

```cpp
    if (settings.contains("rememberFolderView")) {
        m_rememberFolderView = settings.value("rememberFolderView").toBool();
        general.insert_or_assign("remember_folder_view", m_rememberFolderView);
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cmake --build build -j --target tst_configmanager && ctest --test-dir build -R "tst_configmanager$" --output-on-failure`
Expected: PASS (3 new slots + existing config tests).

- [ ] **Step 6: Commit**

```bash
git add src/services/configmanager.h src/services/configmanager.cpp tests/tst_configmanager.cpp
git commit -m "feat(view): rememberFolderView config flag (default on)"
```

---

## Task 5: Wire FolderViewStore into the app

**Files:**
- Modify: `src/main.cpp:41` (include), `:391` (construct), `:468` (context property)

- [ ] **Step 1: Add the include**

In `src/main.cpp`, after line 41 (`#include "models/recentfilesmodel.h"`):

```cpp
#include "models/recentfilesmodel.h"
#include "models/folderviewstore.h"
```

- [ ] **Step 2: Construct the store beside RecentFilesModel**

In `src/main.cpp`, after line 391:

```cpp
    // Create RecentFilesModel
    RecentFilesModel *recentFiles = new RecentFilesModel(configDir + "/recents.json", &app);

    // Per-folder remembered view modes (path -> grid/list/detailed/miller/hybrid).
    FolderViewStore *folderViewStore = new FolderViewStore(configDir + "/folder-views.json", &app);
```

- [ ] **Step 3: Expose it to QML**

In `src/main.cpp`, after line 468 (`...setContextProperty("recentFiles", recentFiles);`):

```cpp
    engine.rootContext()->setContextProperty("recentFiles", recentFiles);
    engine.rootContext()->setContextProperty("folderViewStore", folderViewStore);
```

- [ ] **Step 4: Build to verify it compiles**

Run: `cmake -B build && cmake --build build -j`
Expected: SUCCESS (links `folderviewstore.cpp`, no errors).

- [ ] **Step 5: Commit**

```bash
git add src/main.cpp
git commit -m "feat(view): construct + expose folderViewStore to QML"
```

---

## Task 6: Main.qml — pane-indexed view bindings + folder memory

**Files:**
- Modify: `src/qml/Main.qml` — lines 325 (new prop), 328-338 (mirror refresh), 137/152 (nav hooks), 170-174 region (new handler), 421 (miller guard), 585-595 (subViewFor), helpers (~599), 1636 (PaneFrame), 1690-1693 (StatusBar)

No unit test (QML wiring) — verified by the smoke test + Task 9's manual GUI pass.

- [ ] **Step 1: Add the `paneViewModes` mirror property**

In `src/qml/Main.qml`, after line 325 (`property var panePaths: []`):

```qml
    property var panePaths: []
    // One view mode per live pane, mirror of paneViewMode(index). Same rationale
    // as panePaths: paneViewMode() is an untracked Q_INVOKABLE, so the PaneFrame
    // delegate and footer bind to this array, rebuilt by refreshActivePanePath()
    // and the onPaneViewModeChanged handler.
    property var paneViewModes: []
```

- [ ] **Step 2: Populate the mirror in `refreshActivePanePath`**

In `src/qml/Main.qml`, replace `refreshActivePanePath` (lines 328-338) — add the views loop before the closing brace:

```qml
    function refreshActivePanePath() {
        var t = tabModel.activeTab
        activePanePath = t ? panePath(activePaneIndex) : ""
        activePaneCanGoBack = t ? t.paneCanGoBack(activePaneIndex) : false
        activePaneCanGoForward = t ? t.paneCanGoForward(activePaneIndex) : false
        var paths = []
        var n = t ? t.paneCount : 0
        for (var i = 0; i < n; ++i)
            paths.push(panePath(i))
        panePaths = paths
        var views = []
        for (var k = 0; k < n; ++k)
            views.push(t ? t.paneViewMode(k) : "hybrid")
        paneViewModes = views
    }
```

- [ ] **Step 3: Add the per-pane view-change handler**

In `src/qml/Main.qml`, in the `Connections { target: tabModel.activeTab ... }` block, after `onViewModeChanged` (ends line 174):

```qml
        function onViewModeChanged() {
            if (tabModel.activeTab)
                root.syncMillerParentModel(tabModel.activeTab.currentPath)
            root.scheduleActivePaneFocus()
        }
        function onPaneViewModeChanged(idx) {
            root.refreshActivePanePath()
            if (idx === root.activePaneIndex)
                root.syncMillerParentModel(root.activePanePath)
            root.scheduleActivePaneFocus()
        }
```

- [ ] **Step 4: Apply remembered folder view on navigation**

In `src/qml/Main.qml`, in `onCurrentPathChanged`, after line 137 (`root.refreshActivePanePath()`):

```qml
                root.refreshActivePanePath()
                root.maybeApplyFolderView(0)
```

In `onPanePathChanged(idx)`, after line 152 (`root.refreshActivePanePath()`):

```qml
            root.refreshActivePanePath()
            root.maybeApplyFolderView(idx)
```

- [ ] **Step 5: Make miller-sync read the focused pane's view**

In `src/qml/Main.qml`, replace the guard in `syncMillerParentModel` (line 421):

```qml
    function syncMillerParentModel(path) {
        if (!tabModel.activeTab || root.activePaneViewMode() !== "miller") {
            millerParentModel.setRootPath("")
            return
        }
```

- [ ] **Step 6: Make `subViewFor` read the view's own mode**

In `src/qml/Main.qml`, replace `subViewFor` (lines 585-595):

```qml
    function subViewFor(view) {
        if (!view)
            return null

        var vm = view.viewMode || "hybrid"
        if (vm === "hybrid") return view.hybridViewItem
        if (vm === "grid") return view.gridViewItem
        if (vm === "miller") return view.millerViewItem
        if (vm === "gallery") return view.galleryViewItem
        return view.detailedViewItem
    }
```

- [ ] **Step 7: Add the helper functions**

In `src/qml/Main.qml`, after `activeSubView()` (ends line 599), add:

```qml
    // The focused pane's current view mode, from the reactive mirror.
    function activePaneViewMode() {
        return activePaneIndex < paneViewModes.length
            ? paneViewModes[activePaneIndex]
            : "hybrid"
    }

    // True only for a pane showing a real on-disk folder — folder-view memory
    // never reads or writes for Recents / Hidden / Trash / remote / search panes.
    function isRealFolderPane(idx) {
        if (idx < 0)
            return false
        if (paneIsRecents(idx) || paneIsHidden(idx) || paneSearchMode(idx))
            return false
        var p = panePath(idx)
        if (!p || p === "")
            return false
        return !fileOps.isTrashPath(p) && !fileOps.isRemotePath(p)
    }

    // Footer / shortcut / menu view-switch: set the focused pane's view and,
    // when the setting is on, record it as that folder's remembered view.
    function applyViewToActivePane(mode) {
        if (!tabModel.activeTab)
            return
        var idx = root.activePaneIndex
        tabModel.activeTab.setPaneViewMode(idx, mode)
        if (config.rememberFolderView && root.isRealFolderPane(idx))
            folderViewStore.rememberView(root.panePath(idx), mode)
    }

    // On navigation, apply a folder's remembered view (if any). A miss leaves
    // the pane's current view untouched (sticky-per-pane).
    function maybeApplyFolderView(idx) {
        if (!config.rememberFolderView || !tabModel.activeTab)
            return
        if (!root.isRealFolderPane(idx))
            return
        var saved = folderViewStore.viewForFolder(root.panePath(idx))
        if (saved && saved.length > 0)
            tabModel.activeTab.setPaneViewMode(idx, saved)
    }
```

- [ ] **Step 8: Bind the PaneFrame delegate to its own pane's view**

In `src/qml/Main.qml`, replace line 1636:

```qml
                            paneViewMode: index < root.paneViewModes.length
                                ? root.paneViewModes[index]
                                : (config ? config.defaultView : "hybrid")
```

- [ ] **Step 9: Make the footer reflect + drive the focused pane**

In `src/qml/Main.qml`, replace the StatusBar `viewMode` binding + handler (lines 1688-1693):

```qml
                    // View-switch cluster: reflect and drive the FOCUSED pane's
                    // own view mode (per-pane independent views).
                    viewMode: root.activePaneIndex < root.paneViewModes.length
                        ? root.paneViewModes[root.activePaneIndex]
                        : "hybrid"
                    onViewModeRequested: (m) => root.applyViewToActivePane(m)
```

- [ ] **Step 10: Build + smoke + manual sanity**

Run: `cmake -B build && cmake --build build -j && ctest --test-dir build -R tst_qml_smoke --output-on-failure`
Expected: PASS (QML tree loads with no binding errors).

Then a quick manual check (real GUI, Wayland): `./build/src/wayfile` — split a tab, give each pane a different view via the footer, confirm they stay independent; navigate one pane and confirm its view stays sticky.

- [ ] **Step 11: Commit**

```bash
git add src/qml/Main.qml
git commit -m "feat(view): pane-indexed view bindings + per-folder view memory hooks"
```

---

## Task 7: Route the other view-switch entry points to the focused pane

**Files:**
- Modify: `src/qml/components/AppShortcuts.qml:131,136,141`
- Modify: `src/qml/components/MainOverlays.qml:327-329`

These currently write tab-level `tabModel.activeTab.viewMode`, which would only move pane 0. Both components already hold the root window as `host`.

- [ ] **Step 1: Keyboard shortcuts → focused pane**

In `src/qml/components/AppShortcuts.qml`, replace lines 131, 136, 141:

```qml
        onActivated: { if (host) host.applyViewToActivePane("grid") }
```
```qml
        onActivated: { if (host) host.applyViewToActivePane("miller") }
```
```qml
        onActivated: { if (host) host.applyViewToActivePane("detailed") }
```

(Apply each to its matching Shortcut: `grid_view` → "grid", `miller_view` → "miller", `detailed_view` → "detailed".)

- [ ] **Step 2: Context-menu view actions → focused pane**

In `src/qml/components/MainOverlays.qml`, replace the handler (lines 327-329):

```qml
        onViewModeRequested: (mode) => {
            if (host) host.applyViewToActivePane(mode)
        }
```

- [ ] **Step 3: Build + smoke**

Run: `cmake -B build && cmake --build build -j && ctest --test-dir build -R tst_qml_smoke --output-on-failure`
Expected: PASS.

Manual: with a split tab, focus pane 1 and press the grid/miller/detailed shortcuts and the right-click view menu — only pane 1 changes; pane 0 stays put.

- [ ] **Step 4: Commit**

```bash
git add src/qml/components/AppShortcuts.qml src/qml/components/MainOverlays.qml
git commit -m "feat(view): route shortcut + context-menu view switch to focused pane"
```

---

## Task 8: Settings toggle — "Remember view per folder"

**Files:**
- Modify: `src/qml/components/SettingsPanel.qml` — draft prop (~81), `currentSettings()` (~358), sync/reset (~288)
- Modify: `src/qml/components/SettingsSectionLayout.qml` — add a `Q.Toggle` (after the default-view dropdown, ~line 49)

- [ ] **Step 1: Add the draft property**

In `src/qml/components/SettingsPanel.qml`, after line 81 (`property string draftDefaultView: config.defaultView`):

```qml
    property string draftDefaultView: config.defaultView
    property bool draftRememberFolderView: config.rememberFolderView
```

- [ ] **Step 2: Include it in the saved settings map**

In `src/qml/components/SettingsPanel.qml`, in `currentSettings()`, add to the returned object (after line 358, `defaultView: draftDefaultView,`):

```qml
            defaultView: draftDefaultView,
            rememberFolderView: draftRememberFolderView,
```

- [ ] **Step 3: Re-seed the draft when config syncs**

In `src/qml/components/SettingsPanel.qml`, in the config-sync block, after line 288 (`draftDefaultView = config.defaultView`):

```qml
            draftDefaultView = config.defaultView
            draftRememberFolderView = config.rememberFolderView
```

- [ ] **Step 4: Add the toggle to the Layout section**

In `src/qml/components/SettingsSectionLayout.qml`, after the default-view `SettingDescription` (ends line 49), insert:

```qml
    Q.Toggle {
        Layout.fillWidth: true
        label: "Remember view per folder"
        checked: panel.draftRememberFolderView
        onToggled: (value) => {
            panel.draftRememberFolderView = value
            panel.applySettingsNow()
        }
    }

    SettingDescription {
        text: "When on, each folder reopens in the view you last set for it. New folders keep the current pane's view."
    }
```

- [ ] **Step 5: Build + smoke**

Run: `cmake -B build && cmake --build build -j && ctest --test-dir build -R tst_qml_smoke --output-on-failure`
Expected: PASS (the smoke test loads the default Settings page including this section).

Manual: open Settings → Layout, toggle "Remember view per folder", confirm it persists across an app restart (`~/.config/wayfile/config.toml` shows `remember_folder_view`).

- [ ] **Step 6: Commit**

```bash
git add src/qml/components/SettingsPanel.qml src/qml/components/SettingsSectionLayout.qml
git commit -m "feat(view): Settings toggle for per-folder view memory"
```

---

## Task 9: Full verification + manual GUI gate

**Files:** none (verification only).

- [ ] **Step 1: Full clean build**

Run: `cmake -B build && cmake --build build -j`
Expected: SUCCESS, no warnings about the new sources.

- [ ] **Step 2: Full test suite**

Run: `ctest --test-dir build --output-on-failure`
Expected: all tests PASS, including `tst_folderviewstore`, `tst_tabmodel`, `tst_configmanager`, and `tst_qml_smoke`. (Baseline before this work was 24/24; the new test target makes it 25.)

- [ ] **Step 3: Manual GUI pass (Wayland)**

Run: `./build/src/wayfile` and verify:
- [ ] Split a tab into 2 panes; set pane 0 = grid, pane 1 = detailed via the footer icons — they stay independent.
- [ ] Footer view icons + Ctrl-shortcuts + right-click "View" menu all change ONLY the focused pane.
- [ ] With the setting ON: set Downloads to detailed, navigate away, come back — Downloads reopens detailed. A never-customized folder keeps the pane's current view (no snap).
- [ ] Recents / Trash / a remote mount / active search never trigger a remembered-view change.
- [ ] Toggle the setting OFF in Settings → Layout: per-pane views still work; navigating no longer restores remembered views.
- [ ] Relaunch the app: per-pane views in each split + the customized folders persist; `~/.config/wayfile/folder-views.json` exists with entries.
- [ ] Close a split (supertab) tab, reopen it via Ctrl+Shift+T — each pane comes back with its own view.

- [ ] **Step 4: Update the feature-backlog memory**

Mark WS2 done in `roadmap-feature-backlog.md` and the `MEMORY.md` index line (next workstream becomes WS3/WS4). Commit any spec/plan status edits if needed.

---

## Self-Review Notes

- **Spec coverage:** per-pane setter (T1) · session persistence incl. reopen-closed + legacy (T2) · FolderViewStore w/ LRU + tolerance (T3) · config flag default-on + round-trip (T4) · wiring (T5) · all 5 view-switch entry points rebind to the focused pane — footer (T6), shortcuts + context menu (T7) — plus nav hooks, miller guard, subViewFor (T6) · Settings toggle (T8) · special-view exclusions via `isRealFolderPane` (T6) · verification (T9). The spec's "tst_tablistmodel" maps to `tst_tabmodel` here because that target already links `tablistmodel.cpp` (no separate executable exists).
- **No-clear-button decision:** `FolderViewStore::clear()`/`forget()` exist for tests + future WS3 but are intentionally not surfaced in Settings.
- **Type consistency:** `setPaneViewMode(int,QString)` / `paneViewMode(int)` / `paneViewModeChanged(int)` / `viewForFolder` / `rememberView` / `applyViewToActivePane` / `maybeApplyFolderView` / `isRealFolderPane` / `activePaneViewMode` / `paneViewModes` / `draftRememberFolderView` / `rememberFolderView` / `remember_folder_view` are used identically across all tasks.
