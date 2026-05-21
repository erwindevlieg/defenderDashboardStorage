# Defender Dashboard Storage

Platform for storing historical data from Microsoft Defender XDR and Intune APIs so trends and KPIs are available for dashboards.

> 📚 **Full documentation lives in the [Wiki](https://github.com/erwindevlieg/defenderDashboardStorage/wiki).** This README only covers the quick start.

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
