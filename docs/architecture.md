# Architectuur — Defender Dashboard Storage

## Overzicht

```
┌─────────────────────────────────────────────────────────────┐
│                    GitHub Actions CI/CD                       │
│  validate.yml → deploy-infra.yml → deploy-function.yml      │
└──────────────────────────────┬────────────────────────────────┘
                               │ OIDC
                               ▼
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
│          │  │ Analytics: ExposureScore, SecureScore, │        │
│          │  │   ConfigScore, Alerts, Recommendations │        │
│          │  │ Basic: Devices, Software, AV, Config,  │        │
│          │  │   VulnDelta, Intune*                   │        │
│          │  └───────────────────────────────────────┘        │
│          │             │                                      │
│          │             ▼                                      │
│          │  ┌───────────────────────┐                        │
│          └─▶│ Azure Monitor         │                        │
│             │ Workbooks             │                        │
│             └───────────────────────┘                        │
│                                                               │
│  ┌──────────────────┐  ┌──────────────────┐                 │
│  │ Application       │  │ Alerts            │                 │
│  │ Insights          │  │ (function fail,   │                 │
│  │ (telemetry)       │  │  missing data)    │                 │
│  └──────────────────┘  └──────────────────┘                 │
└─────────────────────────────────────────────────────────────┘
```

## Componenten

| Component | Service | Doel |
|---|---|---|
| **Polling Engine** | Azure Function App (Flex Consumption) | Config-driven API polling |
| **Identity** | User-Assigned Managed Identity | Credential-free authenticatie |
| **Configuratie** | Azure App Configuration | Endpoint definities (zero-code changes) |
| **Ingestie** | Logs Ingestion API (DCR/DCE) | Data transformatie + schrijven naar LA |
| **Opslag** | Log Analytics Workspace | Custom _CL tabellen met per-tabel retentie |
| **Dashboards** | Azure Monitor Workbooks | Interactieve visualisatie |
| **Monitoring** | Application Insights + Alerts | Health monitoring |
| **IaC** | Bicep (modulair) | Alle infra als code |
| **CI/CD** | GitHub Actions (OIDC) | Geautomatiseerde deployment |

## Beveiligingsmodel

- **Authenticatie:** Entra ID only (`disableLocalAuth: true`)
- **Autorisatie:** ABAC-condities op Log Analytics Data Reader per persona
- **Netwerk:** Publiek met RBAC (migreerbaar naar Private Link)
- **Versleuteling:** Microsoft-Managed Keys (AES-256)

## API Endpoints

### Dagelijks (06:00 UTC)
- Exposure Score, Configuration Score, Secure Score
- Recommendations, Vulnerability Delta, Alert Aggregates

### Wekelijks (maandag 08:00 UTC)
- Device Inventory, Software Inventory, AV Health
- Secure Config Assessment
- Intune: managedDevices, detectedApps, compliance reports
