# Een nieuwe databron toevoegen

Dit document beschrijft hoe je een nieuwe API-databron toevoegt aan het platform.

Je past drie bestanden aan en compileert daarna `azuredeploy.json` opnieuw:

1. **`infra/modules/workspace.bicep`** — nieuwe tabel in Log Analytics
2. **`infra/modules/dcr.bicep`** — stream declaratie + data flow in de juiste DCR
3. **`function-app/config/endpoints.json`** **én** **`infra/modules/app-config.bicep`** — polling configuratie

Optioneel: voeg `expected_columns` toe voor schema-validatie tijdens ingestie (zie stap 3).

We gebruiken **Entra Risky Users** als doorlopend voorbeeld in dit document.

---

## Stap 1: Tabel toevoegen in `workspace.bicep`

Voeg een nieuw `resource`-blok toe in [`infra/modules/workspace.bicep`](../infra/modules/workspace.bicep):

```bicep
resource tableEntraRiskyUsers 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'EntraRiskyUsers_CL'
  properties: {
    plan: 'Analytics'        // of 'Basic' voor archief-data
    retentionInDays: 365     // alleen voor Analytics plan
    totalRetentionInDays: 1826
    schema: {
      name: 'EntraRiskyUsers_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }   // verplicht
        { name: 'UserId', type: 'string' }
        { name: 'UserPrincipalName', type: 'string' }
        { name: 'RiskLevel', type: 'string' }
        { name: 'RiskState', type: 'string' }
        { name: 'RiskLastUpdatedDateTime', type: 'datetime' }
      ]
    }
  }
}
```

### Keuze: Analytics vs Basic

| Plan | Kosten | Query snelheid | Gebruik voor |
|---|---|---|---|
| **Analytics** | Hoger | Snel (volledige KQL) | Dashboard data die vaak bevraagd wordt |
| **Basic** | Lager | Trager (30 dagen interactief) | Snapshots, archief-data |

> ⚠️ Een tabel van Analytics naar Basic wijzigen is **onomkeerbaar**.

### Kolom types

| Type | Voorbeeld |
|---|---|
| `string` | IDs, namen, categorieën |
| `int` | Aantallen |
| `real` | Scores, percentages |
| `datetime` | Tijdstempels |
| `boolean` | Vlaggen (IsCompliant, IsApplicable) |
| `dynamic` | JSON objecten of arrays |

---

## Stap 2: Stream + data flow toevoegen in `dcr.bicep`

Open [`infra/modules/dcr.bicep`](../infra/modules/dcr.bicep) en voeg toe aan de juiste DCR (`dcrDailyScores`, `dcrWeeklySnapshots`, of `dcrIntune`).

### A. Stream declaratie

Binnen `streamDeclarations` van de DCR:

```bicep
'Custom-EntraRiskyUsers_CL': {
  columns: [
    { name: 'TimeGenerated', type: 'datetime' }
    { name: 'UserId', type: 'string' }
    { name: 'UserPrincipalName', type: 'string' }
    { name: 'RiskLevel', type: 'string' }
    { name: 'RiskState', type: 'string' }
    { name: 'RiskLastUpdatedDateTime', type: 'datetime' }
  ]
}
```

> De kolommen moeten **exact overeenkomen** met de tabel in `workspace.bicep`. Verschillen leiden stilzwijgend tot dataverlies.

### B. Data flow

Binnen `dataFlows` van dezelfde DCR:

```bicep
{
  streams: [ 'Custom-EntraRiskyUsers_CL' ]
  destinations: [ 'defender-dashboard-workspace' ]
  transformKql: 'source | extend TimeGenerated = now()'
  outputStream: 'Custom-EntraRiskyUsers_CL'
}
```

### Welke DCR?

| DCR | Schedule | Gebruik voor |
|---|---|---|
| `dcrDailyScores` | Dagelijks 06:00 UTC | Scores, alerts, recommendations |
| `dcrWeeklySnapshots` | Wekelijks maandag 08:00 UTC | Device/software inventarisaties |
| `dcrIntune` | Wekelijks maandag 08:00 UTC | Intune-specifieke data |

---

## Stap 3: Endpoint registreren

De polling-engine leest endpoints uit Azure App Configuration en valt terug op `endpoints.json`. Update **beide** zodat lokale tests én production hetzelfde gedrag tonen.

### A. `function-app/config/endpoints.json`

Voeg toe aan de juiste schedule-array (`daily` of `weekly`):

```json
{
  "key": "entraRiskyUsers",
  "url": "https://graph.microsoft.com/v1.0/identityProtection/riskyUsers",
  "method": "GET",
  "scope": "https://graph.microsoft.com/.default",
  "stream": "Custom-EntraRiskyUsers_CL",
  "dcr": "daily",
  "transform": "graphList",
  "expected_columns": [
    "TimeGenerated",
    "UserId",
    "UserPrincipalName",
    "RiskLevel",
    "RiskState",
    "RiskLastUpdatedDateTime"
  ]
}
```

### B. `infra/modules/app-config.bicep`

Voeg een `Microsoft.AppConfiguration/configurationStores/keyValues` resource toe:

```bicep
resource kvEntraRiskyUsers 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'endpoints:daily:entraRiskyUsers'
  properties: {
    value: '{"url": "https://graph.microsoft.com/v1.0/identityProtection/riskyUsers", "method": "GET", "scope": "https://graph.microsoft.com/.default", "stream": "Custom-EntraRiskyUsers_CL", "dcr": "daily", "transform": "graphList", "expected_columns": ["TimeGenerated","UserId","UserPrincipalName","RiskLevel","RiskState","RiskLastUpdatedDateTime"]}'
    contentType: 'application/json'
  }
}
```

### Stream naming conventie

Gebruik altijd het prefix `Custom-` gevolgd door de tabelnaam (incl. `_CL`):

```
Custom-<TableName>_CL
```

### Transform types

De engine ondersteunt vijf transformaties op de API-response voordat records naar de DCR gaan:

| Transform | API response formaat | Output | Gebruik voor |
|---|---|---|---|
| `single` | `{ "score": 42 }` | `[{ "score": 42 }]` | Eén object (Exposure Score, Configuration Score) |
| `list` | `{ "value": [...] }` | `[...]` | Defender REST APIs met value-array |
| `graphList` | `{ "value": [...] }` | `[...]` | Microsoft Graph collecties (functioneel gelijk aan `list`; behouden voor leesbaarheid) |
| `exportList` | `{ "value": [...] }` | `[...]` | Defender export-APIs (machines/SoftwareInventoryByMachine, etc.) |
| `advancedHunting` | `{ "Schema": [...], "Results": [...] }` | `[...]` (uit `Results`) | KQL-queries via `/api/advancedqueries/run` |

Voor `advancedHunting` is een extra veld `query` verplicht met de KQL-string. Zie bestaande voorbeelden in [`endpoints.json`](../function-app/config/endpoints.json) (`asrEvents`, `protectionState`).

### Scope waarden

| API | Scope |
|---|---|
| Defender for Endpoint | `https://api.securitycenter.microsoft.com/.default` |
| Microsoft Graph | `https://graph.microsoft.com/.default` |

### Schema-validatie (`expected_columns`)

Het veld `expected_columns` is **optioneel** maar sterk aanbevolen. De ingestion-laag waarschuwt bij elke run als records kolommen bevatten die niet in deze lijst staan, en filtert ze weg vóór upload. Dit voorkomt stille dataverliezen door schema-mismatches tussen DCR en Log Analytics-tabel.

Standaard gedraagt de engine zich **lenient** (waarschuwen + filteren). Zet `INGESTION_STRICT_SCHEMA=true` op de Function App om de upload te laten falen bij elke mismatch.

---

## Stap 4: Compileren, testen en deployen

```bash
# Bicep valideren
az bicep build --file infra/main.bicep

# ARM template hergenereren voor de Deploy to Azure knop
az bicep build --file infra/main.bicep --outfile azuredeploy.json

# Lokale tests draaien
cd function-app
pytest tests/ -v

# Lint
ruff check . && ruff format --check .
```

Commit alle gewijzigde bestanden:

```bash
git add infra/ function-app/config/endpoints.json azuredeploy.json
git commit -m "feat: add Entra Risky Users connector"
```

Daarna opnieuw deployen:

- **Deploy to Azure**-knop opnieuw klikken (idempotent — alleen nieuwe resources worden aangemaakt)
- Of: `az deployment group create --resource-group rg-defender-dashboard --template-file infra/main.bicep --parameters infra/main.bicepparam`

> Als je bij de eerste deployment een `repoUrl` hebt opgegeven, wordt de Function App-code automatisch uit GitHub gepulled.

---

## Data koppelen tussen tabellen

Gebruik deze kolommen om tabellen aan elkaar te linken:

| Kolom | Doel |
|---|---|
| `DeviceId` | MDE device ID — koppelt alle Defender device-tabellen |
| `AadDeviceId` | Entra device ID — brug tussen Defender en Intune |
| `SoftwareId` | Koppelt SoftwareInventory ↔ VulnDelta ↔ DeviceSoftware |
| `RelatedSoftwareId` | Koppelt Recommendations → SoftwareInventory |
| `UserId` | Entra user ID — brug tussen Risky Users, sign-ins, audit logs |

> Voeg bij device-level data altijd `DeviceId` en `AadDeviceId` toe voor maximale koppelbaarheid.

---

## Permissies

Als de nieuwe databron extra API-permissies vereist:

1. **`infra/scripts/assign-app-roles.ps1`** — voeg de app role GUID toe
2. **`docs/bootstrap.md`** — documenteer de nieuwe permissie

Voor Entra Risky Users heb je `IdentityRiskyUser.Read.All` op Microsoft Graph nodig.
