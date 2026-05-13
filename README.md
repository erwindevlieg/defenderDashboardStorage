# Defender Dashboard Storage

Platform voor het opslaan van historische data uit Microsoft Defender XDR en Intune APIs, zodat trends en KPIs beschikbaar zijn voor dashboards.

## Deploy to Azure

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ferwindevlieg%2FdefenderDashboardStorage%2Fmain%2Fazuredeploy.json)

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
| `repoUrl` | GitHub repo URL — vult automatisch Function App code in | |
| `repoBranch` | Branch voor code-deployment (default: `main`) | |
| `managementGroupObjectId` | Object ID van de management security group | |
| `werkplekGroupObjectId` | Object ID van de werkplek security group | |
| `securityGroupObjectId` | Object ID van de security security group | |
| `scriptRunnerIdentityId` | UAMI resource ID voor app role bootstrap | |

## Na deployment

### 1. Function App code

Als je bij deployment de `repoUrl` parameter hebt ingevuld, wordt de code automatisch uit GitHub gepulled. Je hoeft dan niets extra's te doen.

**Zonder repoUrl?** Deploy handmatig:

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

## Databron toevoegen

Kopieer `infra/custom/_example.bicep`, pas het aan, en activeer het in `infra/custom/custom.bicep`. Voeg een endpoint toe in `endpoints.json` en deploy opnieuw.

Zie [docs/adding-connectors.md](docs/adding-connectors.md) voor de volledige stap-voor-stap handleiding.

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
infra/           — Bicep templates (modulair)
function-app/    — Azure Function App (Python)
workbooks/       — Azure Monitor Workbook ARM templates
docs/            — Documentatie
azuredeploy.json — ARM template (voor Deploy to Azure knop)
```

## Licentie

MIT
