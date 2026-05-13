# Een nieuwe databron toevoegen

Dit document beschrijft hoe je een nieuwe API-databron toevoegt aan het platform.

## Snelle methode: custom folder

De makkelijkste manier is via de `infra/custom/` folder:

1. **Kopieer** `infra/custom/_example.bicep` naar bijv. `infra/custom/entra-risky-users.bicep`
2. **Pas aan:** tabelnaam, kolommen, stream naam, DCR naam
3. **Activeer** in `infra/custom/custom.bicep` door een module-blok toe te voegen:
   ```bicep
   module entraRiskyUsers 'entra-risky-users.bicep' = {
     name: 'deploy-custom-entra-risky-users'
     params: {
       workspaceId: workspaceId
       dceId: dceId
       location: location
       resourceToken: resourceToken
       tags: tags
     }
   }
   ```
4. **Endpoint toevoegen** in `function-app/config/endpoints.json`
5. **Recompile:** `az bicep build --file infra/main.bicep --outfile azuredeploy.json`
6. **Deploy** opnieuw (Deploy to Azure knop of `az deployment group create`)

> Het voorbeeld (`_example.bicep`) bevat een volledig werkende Entra Risky Users connector met commentaar bij elke stap.

---

## Handmatige methode (bestaande modules aanpassen)

Alternatief kun je de bestaande modules direct aanpassen. Dit is handig als je een endpoint wilt toevoegen aan een bestaande DCR.

## Overzicht

Om een nieuwe databron toe te voegen pas je aan:

1. **`infra/modules/workspace.bicep`** — nieuwe tabel in Log Analytics
2. **`infra/modules/dcr.bicep`** — stream declaratie + data flow in de juiste DCR
3. **`function-app/config/endpoints.json`** — polling configuratie voor de Function App

Daarna recompile je `azuredeploy.json` en deploy je opnieuw.

## Stap 1: Tabel toevoegen in workspace.bicep

Voeg een nieuw `resource` blok toe in `infra/modules/workspace.bicep`:

```bicep
resource tableMyNewSource 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'MyNewSource_CL'
  properties: {
    plan: 'Analytics'        // of 'Basic' voor archief-data
    retentionInDays: 365     // alleen voor Analytics plan
    totalRetentionInDays: 1826
    schema: {
      name: 'MyNewSource_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }  // verplicht
        { name: 'ItemId', type: 'string' }
        { name: 'Score', type: 'real' }
        { name: 'IsActive', type: 'boolean' }
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

## Stap 2: Stream toevoegen in dcr.bicep

Open `infra/modules/dcr.bicep` en voeg toe aan de juiste DCR:

### A. Stream declaratie

Voeg toe binnen `streamDeclarations` van de juiste DCR (`dcrDailyScores`, `dcrWeeklySnapshots`, of `dcrIntune`):

```bicep
'Custom-MyNewSource_CL': {
  columns: [
    { name: 'TimeGenerated', type: 'datetime' }
    { name: 'ItemId', type: 'string' }
    { name: 'Score', type: 'real' }
    { name: 'IsActive', type: 'boolean' }
  ]
}
```

> De kolommen moeten **exact overeenkomen** met de tabel in workspace.bicep.

### B. Data flow

Voeg toe binnen `dataFlows` van dezelfde DCR:

```bicep
{
  streams: [ 'Custom-MyNewSource_CL' ]
  destinations: [ 'defender-dashboard-workspace' ]
  transformKql: 'source | extend TimeGenerated = now()'
  outputStream: 'Custom-MyNewSource_CL'
}
```

### Welke DCR?

| DCR | Schedule | Gebruik voor |
|---|---|---|
| `dcrDailyScores` | Dagelijks 06:00 UTC | Scores, alerts, recommendations |
| `dcrWeeklySnapshots` | Wekelijks maandag 08:00 UTC | Device/software inventarisaties |
| `dcrIntune` | Wekelijks maandag 08:00 UTC | Intune-specifieke data |

## Stap 3: Endpoint toevoegen in endpoints.json

Open `function-app/config/endpoints.json` en voeg toe aan het juiste schedule-blok (`daily` of `weekly`):

```json
{
  "key": "myNewSource",
  "url": "https://graph.microsoft.com/v1.0/...",
  "method": "GET",
  "scope": "https://graph.microsoft.com/.default",
  "stream": "Custom-MyNewSource_CL",
  "dcr": "daily",
  "transform": "graphList"
}
```

### Transform types

| Transform | API response formaat | Gebruik voor |
|---|---|---|
| `single` | `{ "score": 42 }` | Enkel object (bijv. Exposure Score) |
| `list` | `{ "value": [...] }` | Defender-stijl lijst |
| `graphList` | `{ "value": [...], "@odata.nextLink": "..." }` | Microsoft Graph API |
| `exportList` | `{ "value": [...] }` | Defender export/assessment APIs |

### Scope waarden

| API | Scope |
|---|---|
| Defender for Endpoint | `https://api.securitycenter.microsoft.com/.default` |
| Microsoft Graph | `https://graph.microsoft.com/.default` |

## Stap 4: Compileren en deployen

```bash
# Bicep valideren
az bicep build --file infra/main.bicep

# Deploy to Azure template bijwerken
az bicep build --file infra/main.bicep --outfile azuredeploy.json

# Committen
git add infra/ function-app/config/endpoints.json azuredeploy.json
git commit -m "feat: add MyNewSource connector"
```

Daarna opnieuw deployen:
- **Deploy to Azure knop** opnieuw klikken (idempotent — alleen nieuwe resources worden aangemaakt)
- Of: `az deployment group create --resource-group rg-defender-dashboard --template-file infra/main.bicep --parameters infra/main.bicepparam`

Na infra-deployment ook de Function App code opnieuw deployen:
```bash
cd function-app
func azure functionapp publish <functionAppName> --python
```

## Data koppelen

Gebruik deze kolommen om tabellen aan elkaar te linken:

| Kolom | Doel |
|---|---|
| `DeviceId` | MDE device ID — koppelt alle Defender device-tabellen |
| `AadDeviceId` | Entra device ID — brug tussen Defender en Intune |
| `SoftwareId` | Koppelt SoftwareInventory ↔ VulnDelta ↔ DeviceSoftware |
| `RelatedSoftwareId` | Koppelt Recommendations → SoftwareInventory |

> Voeg bij device-level data altijd `DeviceId` en `AadDeviceId` toe voor maximale koppelbaarheid.

## Permissies

Als de nieuwe databron extra API-permissies vereist:

1. **`infra/scripts/assign-app-roles.ps1`** — voeg de app role GUID toe
2. **`docs/bootstrap.md`** — documenteer de nieuwe permissie
