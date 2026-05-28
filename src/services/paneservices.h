#pragma once

#include <QObject>
#include <QList>

class FileSystemModel;
class GitStatusService;
class SearchService;
class SearchResultsModel;
class SearchProxyModel;

// Five backend objects that together drive one pane.  Phase 1 main.cpp had
// these inline as a local struct; Phase 2 P2-M6 lifts the type into a
// header so PaneServicesProvider (also here) can hold them and QML can
// reach the slot at idx 2 or 3 by index.
struct PaneServices {
    FileSystemModel *fsModel = nullptr;
    SearchResultsModel *searchResults = nullptr;
    SearchProxyModel *searchProxy = nullptr;
    SearchService *searchService = nullptr;
    GitStatusService *gitService = nullptr;
};

// Q_INVOKABLE indexed accessor over a QList<PaneServices> the way Main.qml
// addresses pane backends in the M6 paneRow Repeater.  Slots 0 / 1 are
// also still exposed under the historical names fsModel / splitFsModel /
// etc., so this provider exists alongside them rather than replacing
// every call site.
class PaneServicesProvider : public QObject {
    Q_OBJECT
    Q_PROPERTY(int count READ count CONSTANT)

public:
    explicit PaneServicesProvider(QObject *parent = nullptr) : QObject(parent) {}

    void setServices(const QList<PaneServices> &services) { m_services = services; }
    int count() const { return m_services.size(); }

    // Returns QObject* so the moc-generated wrapper for these Q_INVOKABLEs
    // doesn't need the concrete service types' headers (forward-declared
    // above).  Implementations live in paneservices.cpp where the model
    // headers are included and static_cast<QObject*> is valid.
    Q_INVOKABLE QObject *fsModelAt(int idx) const;
    Q_INVOKABLE QObject *searchResultsAt(int idx) const;
    Q_INVOKABLE QObject *searchProxyAt(int idx) const;
    Q_INVOKABLE QObject *searchServiceAt(int idx) const;
    Q_INVOKABLE QObject *gitServiceAt(int idx) const;

private:
    bool inRange(int idx) const { return idx >= 0 && idx < m_services.size(); }
    QList<PaneServices> m_services;
};
