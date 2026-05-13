# Defender Dashboard Storage

Platform voor het opslaan van historische data uit Microsoft Defender XDR en Intune APIs, zodat trends en KPIs beschikbaar zijn voor dashboards.

## Deploy to Azure

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2F__OWNER__%2FdefenderDashboardStorage%2Fmain%2Fazuredeploy.json)

> **Let op:** Pas de URL hierboven aan met je eigen GitHub gebruikersnaam/organisatie in plaats van `__OWNER__`.

### Wat wordt er gedeployed?

| Resource | Doel |
|---|---|
| User-Assigned Managed Identity | Authenticatie naar Defender/Graph APIs |
| Log Analytics Workspace | Opslag van alle historische data (14 custom tabellen) |
| Data Collection Endpoint + 3 DCRs | Data-ingestie pipeline |
| Function App (Flex Consumption) | Dagelijkse/wekelijkse API polling |
| App Configuration | Endpoint configuratie (zero-code wijzigingen) |
| Application Insights + Alerts | Monitoring en alerting |
| RBAC assignments | Per-persona toegang (management, werkplek, security) |

### Parameters

| Parameter | Beschrijving | Verplicht |
|---|---|---|
| `resourceToken` | Uniek token voor resource namen (3-10 tekens, bijv. `prod01`) | ✅ |
| `location` | Azure regio (default: resource group locatie) | |
| `managementGroupObjectId` | Object ID van de management security group | |
| `werkplekGroupObjectId` | Object ID van de werkplek security group | |
| `securityGroupObjectId` | Object ID van de security security group | |
| `scriptRunnerIdentityId` | UAMI resource ID voor app role bootstrap | |

## Na deployment

### 1. Function App code deployen

```bash
cd function-app
func azure functionapp publish <functionAppName> --python
```

Of via VS Code: open de `function-app/` map en gebruik de Azure Functions extensie.

### 2. Bootstrap (eenmalig)

Zie [docs/bootstrap.md](docs/bootstrap.md) voor:
- Entra security groups aanmaken
- App role assignments toewijzen aan de Managed Identity
- Eerste test-run valideren

## Architectuur

- **Compute:** Azure Function App (Python 3.11, Flex Consumption)
- **Opslag:** Log Analytics Workspace (dedicated, geen Sentinel)
- **Ingestion:** Logs Ingestion API via Data Collection Rules (DCR/DCE)
- **Auth:** User-Assigned Managed Identity
- **Config:** Azure App Configuration (zero-code endpoint wijzigingen)
- **Dashboards:** Azure Monitor Workbooks
- **IaC:** Bicep (modulair) + Deploy to Azure

## Connector toevoegen (pluggable)

Voeg een YAML-bestand toe aan `connectors/` en draai de generator:

```bash
python scripts/generate.py
```

Zie [docs/adding-connectors.md](docs/adding-connectors.md) voor de volledige handleiding.

## Lokaal ontwikkelen

```bash
cd function-app

# Dependencies installeren
pip install -r requirements.txt

# Tests draaien
pip install pytest pytest-asyncio
pytest tests/ -v

# Linting
pip install ruff
ruff check .
ruff format --check .
```

## Projectstructuur

```
connectors/      — YAML connector manifests (single source of truth)
infra/           — Bicep templates (modulair)
infra/generated/ — Auto-gegenereerde Bicep (vanuit connectors/)
function-app/    — Azure Function App (Python)
workbooks/       — Azure Monitor Workbook ARM templates
scripts/         — Generator en helper scripts
docs/            — Documentatie
azuredeploy.json — ARM template (voor Deploy to Azure knop)
```

## Licentie

MIT
