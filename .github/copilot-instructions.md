# Copilot Instructions

This repository is the **Defender Dashboard Storage** platform — an Azure Function App that polls Microsoft Defender XDR and Intune APIs and stores historical data in Log Analytics for dashboards.

## Architecture

- **Compute:** Azure Function App (Python 3.11, Flex Consumption)
- **Storage:** Log Analytics Workspace (dedicated, no Sentinel)
- **Ingestion:** Logs Ingestion API via Data Collection Rules (DCR/DCE)
- **Auth:** User-Assigned Managed Identity
- **Config:** Azure App Configuration (endpoint definitions)
- **Dashboards:** Azure Monitor Workbooks
- **IaC:** Bicep (modular, in `infra/`)
- **Deploy:** "Deploy to Azure" button (`azuredeploy.json`)

## Build & Test

```bash
# Python tests
cd function-app && pip install -r requirements.txt && pytest tests/ -v

# Linting
pip install ruff && ruff check function-app/ && ruff format --check function-app/

# Bicep validation
az bicep build --file infra/main.bicep

# Recompile Deploy-to-Azure template
az bicep build --file infra/main.bicep --outfile azuredeploy.json
```

## Key Conventions

- **Pluggable:** Add a new data source by editing 3 files (`workspace.bicep`, `dcr.bicep`, `endpoints.json`). See the [Adding Connectors wiki page](https://github.com/erwindevlieg/defenderDashboardStorage/wiki/Adding-Connectors).
- All Bicep modules are in `infra/modules/` and orchestrated by `infra/main.bicep`.
- Python code follows the Azure Functions v2 programming model.
- Config-driven polling: endpoint definitions live in Azure App Configuration (fallback: `function-app/config/endpoints.json`).
- Custom Log Analytics tables use the `_CL` suffix.
- All code, comments, docstrings and documentation are English-only.
- Documentation lives in the [GitHub Wiki](https://github.com/erwindevlieg/defenderDashboardStorage/wiki); the repo only ships the `README.md`.
- Per-persona access via ABAC conditions on the Log Analytics Data Reader role.
- After changing Bicep, recompile `azuredeploy.json` for the Deploy-to-Azure button.
- Endpoints are polled in parallel within a single run; cap via `POLL_CONCURRENCY` (default 5).
