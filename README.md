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
| `scriptRunnerIdentityId` | Resource ID of a UAMI with `AppRoleAssignment.ReadWrite.All` — auto-assigns API permissions when set | |

### 2. Assign API permissions

If you did **not** provide `scriptRunnerIdentityId`, you have to grant Defender + Graph app roles to the Managed Identity manually. See **[Wiki → Bootstrap](https://github.com/erwindevlieg/defenderDashboardStorage/wiki/Bootstrap)** for the PowerShell snippet and full permission list.

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
