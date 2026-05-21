# Defender Dashboard Storage

Platform for storing historical data from Microsoft Defender XDR and Intune APIs so trends and KPIs are available for dashboards.

> 📚 **Full documentation lives in the [Wiki](https://github.com/erwindevlieg/defenderDashboardStorage/wiki).** This README only covers the quick start.

## Not a replacement for Microsoft Sentinel

**If you can use Microsoft Sentinel, use Sentinel.** Sentinel is the recommended, fully-supported path for long-term retention, detections, hunting and dashboards on top of Defender XDR and Intune data. It ships built-in connectors, analytics rules, UEBA, SOAR and workbooks that this project does not attempt to replicate.

This project exists for the cases where Sentinel is not an option, for example:

- Organisations that have decided — for cost, licensing or policy reasons — not to deploy Sentinel.
- Environments where Sentinel is not yet available or cannot be deployed in the target tenant/region.
- Teams (typically endpoint, workplace or service-management) that need historical Defender/Intune KPIs for their own dashboards but are not allowed access to the SOC's Sentinel workspace.

In those scenarios this Function App polls the Defender XDR and Intune APIs and lands the data in a dedicated Log Analytics workspace (no Sentinel solution attached), so the consuming team owns its own data, retention and RBAC — without touching the SOC's environment.

## Quick start

### 1. Deploy

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ferwindevlieg%2FdefenderDashboardStorage%2Fmain%2Fazuredeploy.json)

Create a resource group (e.g. `rg-defender-dashboard`), click the button, and fill in:

| Parameter | What to fill in | Required |
| --- | --- | --- |
| `resourceToken` | Short unique token for resource names, e.g. `prod01` (3–10 chars) | ✅ |
| `repoUrl` | Your fork URL — Python code is auto-deployed when set | |
| `scriptRunnerIdentityId` | Resource ID of a UAMI with `AppRoleAssignment.ReadWrite.All` — auto-assigns the Defender + Graph app roles when set, leave empty to assign them yourself afterwards | |

The deployment **always** creates a User-Assigned Managed Identity for the Function App and binds it to Log Analytics (`Monitoring Metrics Publisher` on the DCR), App Configuration (`App Configuration Data Reader`) and Storage (`Storage Table Data Contributor`). You do not need to create that identity or assign those Azure roles yourself.

### 2. Grant Defender + Graph app roles

The dashboard's Managed Identity also needs **app-role grants** on Microsoft Graph and the Defender XDR / WindowsDefenderATP service principals (e.g. `SecurityRecommendation.Read.All`, `Machine.Read.All`, `DeviceManagementManagedDevices.Read.All`). These cannot be assigned through the normal Azure RBAC plane — they require a Graph API call with `AppRoleAssignment.ReadWrite.All`. Pick one of two paths:

- **Automatic** — provide `scriptRunnerIdentityId` (Resource ID of an existing UAMI that already holds `AppRoleAssignment.ReadWrite.All` on Microsoft Graph). The deployment then runs a `deploymentScript` that grants every required app role to the dashboard MI. After the deploy finishes, you are done.
- **Manual** — leave `scriptRunnerIdentityId` empty. The deploy still succeeds, but the function will get `Forbidden` from the Defender/Graph APIs until you run [`infra/scripts/assign-app-roles.ps1`](infra/scripts/assign-app-roles.ps1) once as a Global Administrator (or Privileged Role Administrator). See **[Wiki → Bootstrap](https://github.com/erwindevlieg/defenderDashboardStorage/wiki/Bootstrap)** for the snippet and full permission list.

> Tip: in enterprise environments it is usually worth creating a one-off "ddash-bootstrap" UAMI with `AppRoleAssignment.ReadWrite.All` and reusing its Resource ID for every future deploy.

#### Pre-create the bootstrap UAMI (one-time, optional)

To enable the **Automatic** path above you first need a UAMI that holds `AppRoleAssignment.ReadWrite.All` on Microsoft Graph. The helper script [`infra/scripts/create-bootstrap-identity.ps1`](infra/scripts/create-bootstrap-identity.ps1) does this end-to-end — create the resource group, create the UAMI, and grant the Graph app role:

```powershell
# Run once, signed in as Global Administrator (or Privileged Role Administrator).
# az login   # against the target tenant/subscription first
./infra/scripts/create-bootstrap-identity.ps1 `
    -ResourceGroup rg-ddash-bootstrap `
    -IdentityName  id-ddash-bootstrap `
    -Location      westeurope
```

The script prints the UAMI's Resource ID. Paste that value into the `scriptRunnerIdentityId` field of every Deploy-to-Azure deployment from then on.

### 3. Verify

Trigger the function manually and check Log Analytics for `_CL` tables. Details in **[Wiki → Runbook](https://github.com/erwindevlieg/defenderDashboardStorage/wiki/Runbook)**.

---

## More

- [Architecture](https://github.com/erwindevlieg/defenderDashboardStorage/wiki/Architecture) — components, data flow, design choices
- [Bootstrap](https://github.com/erwindevlieg/defenderDashboardStorage/wiki/Bootstrap) — API permissions, manual deploy
- [Runbook](https://github.com/erwindevlieg/defenderDashboardStorage/wiki/Runbook) — troubleshooting, KQL examples, alerts
- [Adding Connectors](https://github.com/erwindevlieg/defenderDashboardStorage/wiki/Adding-Connectors) — extend with new data sources

## Development

```bash
cd function-app
pip install -r requirements-dev.txt
pytest tests/ -v
```

Pre-commit runs ruff, mypy, markdownlint and interrogate (`pre-commit install` once, then `pre-commit run --all-files`).

## License

MIT
