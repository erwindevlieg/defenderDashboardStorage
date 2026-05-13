# Defender Dashboard Storage

Platform voor het opslaan van historische data uit Microsoft Defender XDR en Intune APIs, zodat trends en KPIs beschikbaar zijn voor dashboards.

## Architectuur

- **Compute:** Azure Function App (Python 3.11, Flex Consumption)
- **Opslag:** Log Analytics Workspace (dedicated, geen Sentinel)
- **Ingestion:** Logs Ingestion API via Data Collection Rules (DCR/DCE)
- **Auth:** User-Assigned Managed Identity
- **Config:** Azure App Configuration (zero-code endpoint wijzigingen)
- **Dashboards:** Azure Monitor Workbooks
- **IaC:** Bicep (modulair)
- **CI/CD:** GitHub Actions (OIDC)

## Quickstart

### Vereisten

- Azure CLI (`az`) ≥ 2.60
- Bicep CLI (`az bicep`) ≥ 0.28
- Python ≥ 3.11
- Azure Functions Core Tools ≥ 4.x

### Lokaal ontwikkelen

```bash
# Python dependencies
cd function-app
pip install -r requirements.txt

# Tests draaien
pytest tests/

# Linting
pip install ruff
ruff check .
ruff format --check .
```

### Infrastructure deployen

```bash
az deployment group create \
  --resource-group rg-defender-dashboard \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

### Bootstrap (eenmalig)

Zie [docs/bootstrap.md](docs/bootstrap.md) voor eenmalige configuratiestappen (Entra groepen, OIDC federation, app role assignments).

## Projectstructuur

```
infra/           — Bicep templates (modulair)
function-app/    — Azure Function App (Python)
workbooks/       — Azure Monitor Workbook ARM templates
docs/            — Documentatie
.github/         — GitHub Actions workflows
```

## Licentie

Intern gebruik.
