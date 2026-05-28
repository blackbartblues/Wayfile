#include "services/paneservices.h"

#include "models/filesystemmodel.h"
#include "models/searchresultsmodel.h"
#include "models/searchproxymodel.h"
#include "services/gitstatusservice.h"
#include "services/searchservice.h"

QObject *PaneServicesProvider::fsModelAt(int idx) const
{
    return inRange(idx) ? static_cast<QObject *>(m_services[idx].fsModel) : nullptr;
}

QObject *PaneServicesProvider::searchResultsAt(int idx) const
{
    return inRange(idx) ? static_cast<QObject *>(m_services[idx].searchResults) : nullptr;
}

QObject *PaneServicesProvider::searchProxyAt(int idx) const
{
    return inRange(idx) ? static_cast<QObject *>(m_services[idx].searchProxy) : nullptr;
}

QObject *PaneServicesProvider::searchServiceAt(int idx) const
{
    return inRange(idx) ? static_cast<QObject *>(m_services[idx].searchService) : nullptr;
}

QObject *PaneServicesProvider::gitServiceAt(int idx) const
{
    return inRange(idx) ? static_cast<QObject *>(m_services[idx].gitService) : nullptr;
}
