# Adding a New Connector

This project uses a pluggable connector system. Each data source is defined as a single YAML file in the `connectors/` directory. A generator script produces all the infrastructure code automatically.

## Quick Start

### 1. Create a YAML manifest

Create a new file in `connectors/`, e.g. `connectors/my-new-source.yaml`:

```yaml
key: myNewSource                          # Unique identifier (camelCase)
name: My New Data Source                  # Human-readable name
table: MyNewSource_CL                     # Log Analytics table (must end in _CL)
schedule: daily                           # 'daily' or 'weekly'
dcr: daily                                # DCR group: 'daily', 'weekly', or 'intune'
plan: Analytics                           # 'Analytics' (fast queries) or 'Basic' (archive)
retention: 365                            # Interactive retention in days (Analytics only)
totalRetention: 1826                      # Total retention in days

url: https://api.example.com/data         # API endpoint URL
scope: https://api.example.com/.default   # OAuth2 token scope
transform: list                           # Response format (see below)

columns:                                  # Table columns (TimeGenerated is automatic)
  - name: ItemId
    type: string
  - name: Value
    type: real
  - name: IsActive
    type: boolean
```

### 2. Run the generator

```bash
python scripts/generate.py
```

This regenerates:
- `infra/generated/tables.bicep` — Log Analytics table definitions
- `infra/generated/dcr.bicep` — DCR stream declarations and data flows
- `function-app/config/endpoints.json` — Polling configuration

### 3. Commit everything

```bash
git add connectors/my-new-source.yaml
git add infra/generated/ function-app/config/endpoints.json
git commit -m "feat: add My New Source connector"
```

The CI pipeline validates that generated files are up to date.

## Reference

### Column Types

| Type | KQL Type | Example |
|---|---|---|
| `string` | string | Device IDs, names, categories |
| `int` | int | Counts, quantities |
| `real` | real | Scores, percentages |
| `datetime` | datetime | Timestamps |
| `boolean` | bool | Flags (IsCompliant, IsApplicable) |
| `dynamic` | dynamic | JSON objects or arrays |

### Transform Types

| Transform | API Response Format | Use For |
|---|---|---|
| `single` | `{ "score": 42 }` | Single object (e.g., Exposure Score) |
| `list` | `{ "value": [...] }` | Defender-style paginated list |
| `graphList` | `{ "value": [...], "@odata.nextLink": "..." }` | Microsoft Graph API |
| `exportList` | `{ "value": [...] }` | Defender export/assessment APIs |

### Schedule Options

| Schedule | When | Use For |
|---|---|---|
| `daily` | Every day at 06:00 UTC | Scores, alerts, recommendations |
| `weekly` | Every Monday at 08:00 UTC | Inventories, snapshots |

### DCR Groups

| DCR | Purpose |
|---|---|
| `daily` | Daily score and alert data |
| `weekly` | Weekly device/software snapshots |
| `intune` | Intune-specific data |

> **Adding a new DCR group?** Update `dcr_meta` in `scripts/generate.py` and the `dcr_map` in `function-app/polling/engine.py`.

### Table Plan Guidance

| Plan | Cost | Query Speed | Best For |
|---|---|---|---|
| **Analytics** | Higher | Fast (KQL) | Dashboard data queried frequently |
| **Basic** | Lower | Slower (30-day interactive window) | Archive/snapshot data |

> ⚠️ Changing a table from Analytics to Basic is **irreversible**.

## Linking Data

Use these common columns to join tables:

| Column | Purpose |
|---|---|
| `DeviceId` | MDE device identifier — links all Defender device tables |
| `AadDeviceId` | Entra device ID — bridges Defender ↔ Intune |
| `SoftwareId` | Links SoftwareInventory ↔ VulnDelta ↔ DeviceSoftware |
| `RelatedSoftwareId` | Links Recommendations → SoftwareInventory |

When adding a device-level connector, always include `DeviceId` and `AadDeviceId` for maximum joinability.

## Permissions

If your new connector requires additional API permissions, update:
1. `infra/scripts/assign-app-roles.ps1` — add the app role GUID
2. `docs/bootstrap.md` — document the new permission
