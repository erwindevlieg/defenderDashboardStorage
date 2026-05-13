# Defender Dashboard Storage

Platform voor het opslaan van historische data uit Microsoft Defender XDR en Intune APIs, zodat trends en KPIs beschikbaar zijn voor dashboards.

## Snel starten

### Stap 1 — Deploy to Azure

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ferwindevlieg%2FdefenderDashboardStorage%2Fmain%2Fazuredeploy.json)

Maak eerst een resource group aan (bijv. `rg-defender-dashboard` in `West Europe`), klik op de knop hierboven, en vul de parameters in.

### Stap 2 — Wat moet ik invullen?

| Parameter | Wat invullen | Verplicht |
|---|---|---|
| `resourceToken` | Kort uniek token voor resource namen, bijv. `prod01` (3-10 tekens) | ✅ |
| `location` | Azure regio — standaard de locatie van je resource group | |
| `repoUrl` | URL van je fork/clone, bijv. `https://github.com/jouw-user/defenderDashboardStorage` — dan wordt de Python code automatisch gedeployed | |
| `repoBranch` | Branch voor code-deployment — standaard `main` | |
| `scriptRunnerIdentityId` | Resource ID van een bestaande User-Assigned Managed Identity met `AppRoleAssignment.ReadWrite.All`. Formaat: `/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/{naam}`. Als ingevuld worden API-permissies automatisch toegewezen. Laat leeg voor handmatige toewijzing (zie `docs/bootstrap.md`). | |

---

## Wat doet de Deploy knop automatisch?

De knop deployt de **volledige infrastructuur** in één keer:

| Wat | Resource | Automatisch? |
|---|---|---|
| Managed Identity | `uai-defender-dashboard-<token>` | ✅ Altijd |
| Log Analytics Workspace | `law-defender-dashboard-<token>` met 14 custom tabellen | ✅ Altijd |
| Data Collection Endpoint + 3 DCRs | Data-ingestie pipeline | ✅ Altijd |
| Function App | `func-defender-dashboard-<token>` (Python 3.11, Flex Consumption) | ✅ Altijd |
| Storage Account | Voor Function App deployment packages | ✅ Altijd |
| App Configuration | Endpoint configuratie store | ✅ Altijd |
| Application Insights + Alerts | Monitoring en foutmeldingen | ✅ Altijd |
| Function App **code** | Python code uit je GitHub repo | ✅ Als `repoUrl` is ingevuld |
| API-permissies (app roles) | Defender + Graph API-toegang voor de Managed Identity | ✅ Als `scriptRunnerIdentityId` is ingevuld |

---

## Wat moet ik nog handmatig doen?

Dat hangt af van welke optionele parameters je hebt ingevuld:

### ✅ `repoUrl` ingevuld → niets te doen

De Function App code wordt automatisch uit GitHub gepulled.

### ❌ `repoUrl` niet ingevuld → Function App code deployen

```bash
cd function-app
func azure functionapp publish <functionAppName> --python
```

Of via VS Code: open `function-app/` en gebruik de Azure Functions extensie.

### ✅ `scriptRunnerIdentityId` ingevuld → niets te doen

De API-permissies worden automatisch toegewezen via een deployment script.

### ❌ `scriptRunnerIdentityId` niet ingevuld → API-permissies handmatig toewijzen

Dit is de **meest voorkomende** situatie. De Managed Identity heeft app roles nodig op Defender en Graph APIs. Zonder deze stap kan de Function App **geen data ophalen**.

Je hebt de rol **Privileged Role Administrator** nodig (of Global Admin) en de [Microsoft Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/installation):

```powershell
# 1. Installeer Microsoft Graph module (eenmalig)
Install-Module Microsoft.Graph.Applications -Scope CurrentUser

# 2. Login als Privileged Role Administrator
Connect-MgGraph -Scopes "AppRoleAssignment.ReadWrite.All"

# 3. Zoek de principal ID van de Managed Identity
$uamiPrincipalId = (az identity show `
  -g <resourceGroup> `
  -n uai-defender-dashboard-<resourceToken> `
  --query principalId -o tsv)

# 4. Wijs alle Defender + Graph API-permissies toe
.\infra\scripts\assign-app-roles.ps1 -ManagedIdentityPrincipalId $uamiPrincipalId
```

Het script wijst deze permissies toe:

| API | Permissies |
|---|---|
| **Defender XDR** | Score.Read.All, Machine.Read.All, Vulnerability.Read.All, Alert.Read.All, SecurityRecommendation.Read.All, Software.Read.All, AdvancedQuery.Read.All |
| **Microsoft Graph** | SecurityEvents.Read.All, DeviceManagementManagedDevices.Read.All, DeviceManagementConfiguration.Read.All, DeviceManagementApps.Read.All |

> ⚠️ Na het toewijzen kan het tot **1 uur** duren voordat tokens de nieuwe rollen bevatten.

---

## Verificatie

Na alle stappen:

1. **Tabellen** — Controleer in Azure Portal → Log Analytics Workspace → Tables dat alle `_CL` tabellen bestaan
2. **Eerste data** — De Function App draait dagelijks om 06:00 UTC. Trigger handmatig via Azure Portal → Function App → Functions → Timer trigger → "Run"
3. **Monitoring** — Check Application Insights voor eventuele fouten (bijv. `403 Forbidden` = app roles nog niet actief)

---

## Architectuur

```
┌─────────────────┐     ┌───────────────────┐     ┌────────────────────┐
│  Defender XDR    │────▶│   Function App    │────▶│  Log Analytics     │
│  Graph API       │     │   (Python 3.11)   │     │  Workspace         │
│  Intune API      │     │   Flex Consumption│     │  14 custom tabellen│
└─────────────────┘     └───────┬───────────┘     └────────┬───────────┘
                                │                          │
                    ┌───────────┴──────────┐    ┌──────────┴──────────┐
                    │ App Configuration    │    │ DCE + 3 DCRs        │
                    │ (endpoint config)    │    │ (data-ingestie)     │
                    └──────────────────────┘    └─────────────────────┘
```

- **Auth:** User-Assigned Managed Identity (geen secrets)
- **Monitoring:** Application Insights + alerting bij fouten
- **Dashboards:** Azure Monitor Workbooks (zie `workbooks/` map)

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
infra/                — Bicep modules (infrastructuur)
  modules/            — Kern-modules (workspace, dcr, function-app, etc.)
  custom/             — Eigen connectors toevoegen (zie _example.bicep)
  scripts/            — Bootstrap scripts (app role assignments)
function-app/         — Azure Function App (Python)
  engine/             — Polling engine
  config/             — Endpoint configuratie
  tests/              — Pytest tests
workbooks/            — Azure Monitor Workbook templates
docs/                 — Documentatie
azuredeploy.json      — Gecompileerde ARM template (voor Deploy to Azure knop)
```

## Licentie

MIT
