# Defender Dashboard Storage

Platform for storing historical data from Microsoft Defender XDR and Intune APIs, so that trends and KPIs are available for dashboards.

> **Documentation lives in the [Wiki](https://github.com/erwindevlieg/defenderDashboardStorage/wiki).** This README only covers the quick start.

## Quick start

### Step 1 — Deploy to Azure

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ferwindevlieg%2FdefenderDashboardStorage%2Fmain%2Fazuredeploy.json)

Create a resource group first (e.g. `rg-defender-dashboard` in `West Europe`), click the button above, and fill in the parameters.

### Step 2 — What do I need to fill in?

| Parameter | What to fill in | Required |
| --- | --- | --- |
| `resourceToken` | Short unique token for resource names, e.g. `prod01` (3–10 chars) | ✅ |
| `location` | Azure region — defaults to the resource group's location | |
| `repoUrl` | URL of your fork/clone, e.g. `https://github.com/your-user/defenderDashboardStorage` — Python code is then auto-deployed | |
| `repoBranch` | Branch for code deployment — defaults to `main` | |
| `scriptRunnerIdentityId` | Resource ID of an existing User-Assigned Managed Identity with `AppRoleAssignment.ReadWrite.All`. Format: `/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/{name}`. If filled, API permissions are auto-assigned. Leave empty for manual assignment (see [Bootstrap](https://github.com/erwindevlieg/defenderDashboardStorage/wiki/Bootstrap)). | |

---

## What does the Deploy button do automatically?

The button deploys the **entire infrastructure** in one go:

| What | Resource | Automatic? |
| --- | --- | --- |
| Managed Identity | `uai-defender-dashboard-<token>` | ✅ Always |
| Log Analytics Workspace | `law-defender-dashboard-<token>` with 14 custom tables | ✅ Always |
| Data Collection Endpoint + 3 DCRs | Data-ingestion pipeline | ✅ Always |
| Function App | `func-defender-dashboard-<token>` (Python 3.11, Flex Consumption) | ✅ Always |
| Storage Account | For Function App deployment packages | ✅ Always |
| App Configuration | Endpoint configuration store | ✅ Always |
| Application Insights + Alerts | Monitoring and failure notifications | ✅ Always |
| Function App **code** | Python code from your GitHub repo | ✅ When `repoUrl` is set |
| API permissions (app roles) | Defender + Graph API access for the Managed Identity | ✅ When `scriptRunnerIdentityId` is set |

---

## What do I still need to do manually?

Depends on which optional parameters you filled in:

### ✅ `repoUrl` set → nothing to do

The Function App code is pulled automatically from GitHub.

### ❌ `repoUrl` not set → deploy the Function App code

```bash
cd function-app
func azure functionapp publish <functionAppName> --python
```

Or via VS Code: open `function-app/` and use the Azure Functions extension.

### ✅ `scriptRunnerIdentityId` set → nothing to do

API permissions are assigned automatically via a deployment script.

### ❌ `scriptRunnerIdentityId` not set → assign API permissions manually

This is the **most common** situation. The Managed Identity needs app roles on the Defender and Graph APIs. Without this step the Function App **cannot fetch data**.

You need the **Privileged Role Administrator** role (or Global Admin) and the [Microsoft Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/installation):

```powershell
# 1. Install the Microsoft Graph module (once)
Install-Module Microsoft.Graph.Applications -Scope CurrentUser

# 2. Sign in as Privileged Role Administrator
Connect-MgGraph -Scopes "AppRoleAssignment.ReadWrite.All"

# 3. Look up the principal ID of the Managed Identity
$uamiPrincipalId = (az identity show `
  -g <resourceGroup> `
  -n uai-defender-dashboard-<resourceToken> `
  --query principalId -o tsv)

# 4. Assign all Defender + Graph API permissions
.\infra\scripts\assign-app-roles.ps1 -ManagedIdentityPrincipalId $uamiPrincipalId
```

The script assigns these permissions:

| API | Permissions |
| --- | --- |
| **Defender XDR** | Score.Read.All, Machine.Read.All, Vulnerability.Read.All, Alert.Read.All, SecurityRecommendation.Read.All, Software.Read.All, AdvancedQuery.Read.All |
| **Microsoft Graph** | SecurityEvents.Read.All, DeviceManagementManagedDevices.Read.All, DeviceManagementConfiguration.Read.All, DeviceManagementApps.Read.All |

> ⚠️ After assignment it can take up to **1 hour** before tokens contain the new roles.

---

## Verification

After all steps:

1. **Tables** — In the Azure Portal → Log Analytics Workspace → Tables, verify that all `_CL` tables exist.
2. **First data** — The Function App runs daily at 06:00 UTC. Trigger it manually via Azure Portal → Function App → Functions → Timer trigger → "Run".
3. **Monitoring** — Check Application Insights for any errors (e.g. `403 Forbidden` = app roles not yet active).

---

## Architecture (at a glance)

```text
┌─────────────────┐     ┌───────────────────┐     ┌────────────────────┐
│  Defender XDR   │────▶│   Function App    │────▶│  Log Analytics     │
│  Graph API      │     │   (Python 3.11)   │     │  Workspace         │
│  Intune API     │     │   Flex Consumption│     │  14 custom tables  │
└─────────────────┘     └───────┬───────────┘     └────────┬───────────┘
                                │                          │
                    ┌───────────┴──────────┐    ┌──────────┴──────────┐
                    │ App Configuration    │    │ DCE + 3 DCRs        │
                    │ (endpoint config)    │    │ (data ingestion)    │
                    └──────────────────────┘    └─────────────────────┘
```

- **Auth:** User-Assigned Managed Identity (no secrets)
- **Monitoring:** Application Insights + alerts on failures
- **Dashboards:** Azure Monitor Workbooks (see `workbooks/` folder)

For full architecture, runbook, troubleshooting and connector recipes see the [Wiki](https://github.com/erwindevlieg/defenderDashboardStorage/wiki):

- [Architecture](https://github.com/erwindevlieg/defenderDashboardStorage/wiki/Architecture)
- [Bootstrap](https://github.com/erwindevlieg/defenderDashboardStorage/wiki/Bootstrap)
- [Runbook](https://github.com/erwindevlieg/defenderDashboardStorage/wiki/Runbook) — troubleshooting, KQL examples, alerts
- [Adding Connectors](https://github.com/erwindevlieg/defenderDashboardStorage/wiki/Adding-Connectors)

## Local development

```bash
cd function-app

# Install dev dependencies (lint, test, doc coverage)
pip install -r requirements-dev.txt

# Activate pre-commit hooks (ruff, markdownlint, interrogate, ...)
# From repo root:
cd ..
pre-commit install

# Run tests
cd function-app
pytest tests/ -v

# Manual lint
ruff check .
ruff format --check .
mypy polling
interrogate -v polling

# All hooks at once (markdown, yaml, python) over the entire repo:
cd ..
pre-commit run --all-files
```

## Project structure

```text
infra/                — Bicep modules (infrastructure)
  modules/            — Core modules (workspace, dcr, function-app, etc.)
  scripts/            — Bootstrap scripts (app role assignments)
function-app/         — Azure Function App (Python)
  polling/            — Polling engine (engine, clients, ingestion, state)
  config/             — Endpoint configuration (fallback)
  tests/              — Pytest tests
workbooks/            — Azure Monitor Workbook templates
azuredeploy.json      — Compiled ARM template (for the Deploy-to-Azure button)
```

Documentation: [GitHub Wiki](https://github.com/erwindevlieg/defenderDashboardStorage/wiki).

## License

MIT
