# Bootstrap Guide — Defender Dashboard Storage

## Overzicht

Dit document beschrijft de eenmalige configuratiestappen die nodig zijn voordat het platform gedeployed kan worden via GitHub Actions.

---

## 1. GitHub Repository

```bash
# In de projectdirectory
git remote add origin https://github.com/<org>/defenderDashboardStorage.git
git branch -M main
git push -u origin main
```

## 2. Entra ID Security Groups

Maak drie security groups aan in Microsoft Entra ID:

| Groep | Doel |
|---|---|
| `sg-defender-dashboard-management` | C-level/afdelingshoofden — alleen KPI-dashboards |
| `sg-defender-dashboard-werkplek` | Werkplek IT — device/endpoint dashboards |
| `sg-defender-dashboard-security` | SOC/Security — volledige toegang |

```bash
az ad group create --display-name "sg-defender-dashboard-management" --mail-nickname "sg-defender-dashboard-management" --security-enabled true
az ad group create --display-name "sg-defender-dashboard-werkplek" --mail-nickname "sg-defender-dashboard-werkplek" --security-enabled true
az ad group create --display-name "sg-defender-dashboard-security" --mail-nickname "sg-defender-dashboard-security" --security-enabled true
```

Noteer de Object IDs en vul ze in bij `infra/main.bicepparam`.

## 3. Azure Resource Group

```bash
az group create --name rg-defender-dashboard --location westeurope
```

## 4. OIDC Federation voor GitHub Actions

### Optie A: App Registration (aanbevolen voor CI/CD)

```bash
# App Registration aanmaken
az ad app create --display-name "github-defender-dashboard-cicd"

# Noteer de appId
APP_ID=$(az ad app list --display-name "github-defender-dashboard-cicd" --query "[0].appId" -o tsv)

# Service Principal aanmaken
az ad sp create --id $APP_ID

# Federated credential voor GitHub Actions
az ad app federated-credential create --id $APP_ID --parameters '{
  "name": "github-actions-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<org>/defenderDashboardStorage:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'

# RBAC: Contributor op de resource group
az role assignment create \
  --assignee $APP_ID \
  --role Contributor \
  --scope /subscriptions/<sub-id>/resourceGroups/rg-defender-dashboard
```

### GitHub Secrets configureren

Stel de volgende secrets in op de GitHub repository:

| Secret | Waarde |
|---|---|
| `AZURE_CLIENT_ID` | App Registration appId |
| `AZURE_TENANT_ID` | Entra Tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure Subscription ID |

## 5. App Role Assignments (Privileged Role Administrator)

De Managed Identity heeft app roles nodig op WindowsDefenderATP en Microsoft Graph. Dit vereist éénmalig een **Privileged Role Administrator**.

### Optie A: Handmatig via PowerShell

Na de eerste `deploy-infra` run (die de UAMI aanmaakt), voer uit:

```powershell
# Connect als Privileged Role Administrator
Connect-MgGraph -Scopes "AppRoleAssignment.ReadWrite.All"

# Haal de UAMI principal ID op
$uamiPrincipalId = (az identity show -g rg-defender-dashboard -n uai-defender-dashboard-prod01 --query principalId -o tsv)

# Voer het assign-app-roles.ps1 script uit
.\infra\scripts\assign-app-roles.ps1 -ManagedIdentityPrincipalId $uamiPrincipalId
```

### Optie B: Via Bicep deploymentScript

Vul `scriptRunnerIdentityId` in `main.bicepparam` in met de resource ID van een UAMI die `AppRoleAssignment.ReadWrite.All` heeft. De Bicep deployment voert het script dan automatisch uit.

## 6. Eerste Deployment

```bash
# Test lokaal
cd function-app && pip install -r requirements.txt && pytest tests/ -v

# Push naar GitHub → workflows draaien automatisch
git add -A && git commit -m "Initial implementation" && git push
```

## 7. Verificatie

Na deployment:

1. **Function App health check:**
   ```bash
   curl https://func-defender-dashboard-prod01.azurewebsites.net/api/health
   ```

2. **Log Analytics tabellen:** Controleer in Azure Portal dat alle `_CL` tabellen zijn aangemaakt

3. **Eerste data:** Wacht tot de eerste timer trigger draait (06:00 UTC dagelijks) of trigger handmatig via Azure Portal

> ⚠️ **Token propagation:** Na het toewijzen van app roles kan het tot 1 uur duren voordat tokens de nieuwe rollen bevatten. Bij downstream caching kan dit tot 24 uur zijn.
