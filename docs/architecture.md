# Architectuur — Defender Dashboard Storage

## Overzicht

```
┌─────────────────────────────────────────────────────────────┐
│                      Azure Resource Group                    │
│                                                               │
│  ┌──────────────────┐    ┌──────────────────────────────┐   │
│  │ User-Assigned MI  │───▶│ Azure Function App            │   │
│  │ (uai-defender-*)  │    │ Python 3.11, Flex Consumption │   │
│  └──────────────────┘    │ Timer: daily 06:00, weekly    │   │
│          │                └──────────────┬───────────────┘   │
│          │                               │                    │
│          │  ┌───────────────────────┐    │ API calls          │
│          ├─▶│ Azure App Config      │    │                    │
│          │  │ Endpoint definities   │    ▼                    │
│          │  └───────────────────────┘  ┌──────────────┐      │
│          │                             │ Defender API  │      │
│          │                             │ Graph API     │      │
│          │                             │ Intune API    │      │
│          │                             └──────┬───────┘      │
│          │                                    │               │
│          │  ┌───────────────────────┐         │ JSON          │
│          ├─▶│ Data Collection       │◀────────┘               │
│          │  │ Endpoint + Rules      │                         │
│          │  └──────────┬────────────┘                         │
│          │             │ KQL transform                        │
│          │             ▼                                      │
│          │  ┌───────────────────────────────────────┐        │
│          │  │ Log Analytics Workspace                │        │
│          │  │ (law-defender-dashboard-*)             │        │
│          │  │                                        │        │
│          │  │ Analytics: Scores, Alerts, Recommend., │        │
│          │  │   DeviceInventory, AVHealth, VulnDelta,│        │
│          │  │   IntuneDevices                        │        │
│          │  │ Basic: Software, Config, DeviceSoftware│        │
│          │  │   IntuneApps, IntuneCompliance         │        │
│          │  └───────────────────────────────────────┘        │
│          │             │                                      │
│          │             ▼                                      │
│          │  ┌───────────────────────┐                        │
│          └─▶│ Azure Monitor         │                        │
│             │ Workbooks (auto-deploy)│                        │
│             └───────────────────────┘                        │
│                                                               │
│  ┌──────────────────┐  ┌──────────────────┐                 │
│  │ Application       │  │ Alerts + Action   │                 │
│  │ Insights          │  │ Group (e-mail)    │                 │
│  └──────────────────┘  └──────────────────┘                 │
└─────────────────────────────────────────────────────────────┘
```

## Componenten

| Component | Service | Doel |
|---|---|---|
| **Polling Engine** | Azure Function App (Flex Consumption) | Config-driven API polling met retry + backfill |
| **Identity** | User-Assigned Managed Identity | Credential-free authenticatie |
| **Configuratie** | Azure App Configuration | Endpoint definities (zero-code changes) |
| **Ingestie** | Logs Ingestion API (DCR/DCE) | Data transformatie + schrijven naar LA |
| **Opslag** | Log Analytics Workspace | Custom _CL tabellen (Analytics + Basic tier) |
| **Dashboards** | Azure Monitor Workbooks | Auto-deployed via Bicep, incl. data freshness |
| **Monitoring** | Application Insights + Alerts | Health monitoring + e-mail notificaties |
| **IaC** | Bicep (modulair) | Alle infra als code |
| **Deployment** | Deploy to Azure knop | One-click deployment vanuit GitHub |

## Tabel Tiers

### Analytics Plan (volledige KQL, joins, dashboards)

| Tabel | Reden |
|---|---|
| ExposureScore, SecureScore, ConfigurationScore | Score-tijdlijnen, verwaarloosbaar volume |
| AlertAggregates | MTTR/MTTD trends |
| Recommendations | Dashboard aggregaties per severity/status |
| DeviceInventory | Hub-tabel — alles jointed hierop |
| AVHealth | Join met DeviceInventory voor AV status |
| VulnDelta | Join met DeviceInventory voor vulns per device |
| IntuneDevices | Cross-platform join via AadDeviceId |

### Basic Plan (standalone queries, goedkoper)

| Tabel | Reden |
|---|---|
| SoftwareInventory | Standalone catalogus |
| SecureConfig | Groot volume, standalone compliance queries |
| DeviceSoftware | Link-tabel, groot volume |
| IntuneDetectedApps | Geaggregeerd overzicht |
| IntuneComplianceReports | Geaggregeerd overzicht |

## Beveiligingsmodel

- **Authenticatie:** Entra ID only (`disableLocalAuth: true` op alle services)
- **Identity:** User-Assigned Managed Identity (geen secrets)
- **Storage:** Shared key access uitgeschakeld, OAuth-only
- **Netwerk:** Publiek met RBAC (migreerbaar naar Private Link)
- **Versleuteling:** Microsoft-Managed Keys (AES-256)
- **Retry:** 3x exponentieel backoff met Retry-After header support
- **Alerting:** E-mail notificaties bij function failures of ontbrekende data

## API Endpoints

### Dagelijks (06:00 UTC)
- Exposure Score, Configuration Score, Secure Score
- Recommendations, Vulnerability Delta, Alert Aggregates

### Wekelijks (maandag 08:00 UTC)
- Device Inventory, Software Inventory, AV Health
- Secure Config Assessment
- Intune: managedDevices, detectedApps, compliance reports
