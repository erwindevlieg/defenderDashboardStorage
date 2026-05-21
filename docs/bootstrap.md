# Bootstrap Guide — Defender Dashboard Storage

## Overzicht

Dit document beschrijft de stappen om het platform operationeel te maken. De Deploy to Azure knop regelt het meeste automatisch — hieronder staat wat er eventueel nog handmatig nodig is.

---

## Vereisten

| Wat | Waarom |
| --- | --- |
| Azure subscription met Contributor-rechten | Resources aanmaken |
| Privileged Role Administrator (of Global Admin) | API-permissies toewijzen aan de Managed Identity |
| [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) | Handmatige commando's uitvoeren |
| [Microsoft Graph PowerShell SDK](https://learn.microsoft.com/powershell/microsoftgraph/installation) | App role assignments script |

---

## Stap 1 — Resource Group aanmaken

```bash
az group create --name rg-defender-dashboard --location westeurope
```

## Stap 2 — Deploy to Azure

Klik op de knop in de [README](../README.md) of gebruik de directe link:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ferwindevlieg%2FdefenderDashboardStorage%2Fmain%2Fazuredeploy.json)

**Minimaal invullen:**

- `resourceToken` — bijv. `prod01`

**Aanbevolen ook invullen:**

- `repoUrl` — URL van je fork/clone, zodat de Function App code automatisch mee-deployed wordt

Zie de [README](../README.md) voor een beschrijving van alle parameters.

## Stap 3 — API-permissies toewijzen

> ⚡ Als je `scriptRunnerIdentityId` hebt ingevuld bij stap 2, is dit al automatisch gedaan. Sla deze stap dan over.

De Managed Identity heeft app roles nodig op de Defender XDR en Microsoft Graph APIs. Zonder deze permissies krijgt de Function App `403 Forbidden` fouten.

### 3a. Installeer de Microsoft Graph module

```powershell
Install-Module Microsoft.Graph.Applications -Scope CurrentUser -Force
```

### 3b. Login

```powershell
Connect-MgGraph -Scopes "AppRoleAssignment.ReadWrite.All"
```

Je wordt gevraagd om in te loggen. Gebruik een account met **Privileged Role Administrator** of **Global Admin**.

### 3c. Zoek de Managed Identity

```powershell
# Vervang <resourceGroup> en <resourceToken> met jouw waarden
$uamiPrincipalId = (az identity show `
  -g <resourceGroup> `
  -n uai-defender-dashboard-<resourceToken> `
  --query principalId -o tsv)

Write-Output "Principal ID: $uamiPrincipalId"
```

### 3d. Voer het bootstrap-script uit

```powershell
.\infra\scripts\assign-app-roles.ps1 -ManagedIdentityPrincipalId $uamiPrincipalId
```

Het script wijst automatisch alle benodigde permissies toe:

**Defender XDR (WindowsDefenderATP):**

- `Score.Read.All` — Secure Score en Exposure Score
- `Machine.Read.All` — Device inventory en AV health
- `Vulnerability.Read.All` — Kwetsbaarheden en secure config
- `Alert.Read.All` — Alert aggregates
- `SecurityRecommendation.Read.All` — Beveiligingsaanbevelingen
- `Software.Read.All` — Software inventory
- `AdvancedQuery.Read.All` — Advanced Hunting queries (AV status, ASR events, protection state)

**Microsoft Graph:**

- `SecurityEvents.Read.All` — Secure Scores (via Graph)
- `DeviceManagementManagedDevices.Read.All` — Intune devices
- `DeviceManagementConfiguration.Read.All` — Intune compliance
- `DeviceManagementApps.Read.All` — Intune detected apps

> ⚠️ **Token propagation:** Na het toewijzen kan het tot **1 uur** duren voordat tokens de nieuwe rollen bevatten. Bij downstream caching kan dit tot 24 uur zijn. Als je `403` fouten ziet, wacht dan even.

## Stap 4 — Verificatie

### Tabellen controleren

Open Azure Portal → Log Analytics Workspace → Tables. Je zou 14 tabellen moeten zien die eindigen op `_CL`:

- `DefenderExposureScore_CL`, `DefenderSecureScore_CL`, `DefenderConfigScore_CL`
- `DefenderDeviceInventory_CL`, `DefenderAVHealth_CL`, `DefenderSecureConfig_CL`
- `DefenderRecommendations_CL`, `DefenderVulnDelta_CL`, `DefenderAlertAggregates_CL`
- `DefenderDeviceSoftware_CL`
- `IntuneDevices_CL`, `IntuneCompliance_CL`, `IntuneAppInventory_CL`, `IntuneConfigProfiles_CL`

### Eerste data ophalen

De Function App draait automatisch op schema:

- **Dagelijks 06:00 UTC** — scores, alerts, kwetsbaarheden
- **Wekelijks zondag 02:00 UTC** — device inventory, software, Intune

**Handmatig triggeren:** Azure Portal → Function App → Functions → kies een timer function → "Code + Test" → "Run"

### Fouten bekijken

Azure Portal → Application Insights → Failures

Veelvoorkomende fouten:

| Fout | Oorzaak | Oplossing |
| --- | --- | --- |
| `403 Forbidden` | App roles nog niet actief | Wacht tot 1 uur na stap 3 |
| `401 Unauthorized` | Managed Identity niet gekoppeld | Controleer Function App → Identity |
| Geen data na 24u | Timer niet actief | Controleer Function App → Functions |

---

## Opnieuw deployen

De deployment is **idempotent** — je kunt de Deploy to Azure knop opnieuw klikken zonder dat bestaande data verloren gaat. Alleen nieuwe of gewijzigde resources worden aangemaakt/bijgewerkt.

Na wijzigingen aan Bicep-bestanden moet `azuredeploy.json` opnieuw gegenereerd worden:

```bash
az bicep build --file infra/main.bicep --outfile azuredeploy.json
```
