#!/usr/bin/env python3
"""Generate Bicep and endpoints.json from connector YAML manifests.

Usage:
    python scripts/generate.py

Reads all *.yaml files from connectors/ and generates:
  - infra/modules/workspace.generated.bicep  (table definitions)
  - infra/modules/dcr.generated.bicep        (stream declarations + data flows)
  - function-app/config/endpoints.json       (polling configuration)

These generated files are imported by the main Bicep modules.
"""

import json
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is required. Install with: pip install pyyaml")
    sys.exit(1)

ROOT = Path(__file__).resolve().parent.parent
CONNECTORS_DIR = ROOT / "connectors"
INFRA_DIR = ROOT / "infra" / "generated"
FUNCTION_CONFIG = ROOT / "function-app" / "config" / "endpoints.json"


def load_connectors() -> list[dict]:
    """Load and validate all connector YAML files."""
    connectors = []
    required_fields = {"key", "name", "table", "schedule", "dcr", "url", "scope", "transform", "plan", "totalRetention", "columns"}

    for path in sorted(CONNECTORS_DIR.glob("*.yaml")):
        with open(path) as f:
            data = yaml.safe_load(f)

        if data is None:
            print(f"  SKIP: {path.name} (empty file)")
            continue

        missing = required_fields - set(data.keys())
        if missing:
            print(f"  ERROR: {path.name} missing fields: {missing}")
            sys.exit(1)

        # Analytics plan requires retention
        if data["plan"] == "Analytics" and "retention" not in data:
            print(f"  ERROR: {path.name} Analytics plan requires 'retention' field")
            sys.exit(1)

        data["_source"] = path.name
        connectors.append(data)

    return connectors


def generate_workspace_bicep(connectors: list[dict]) -> str:
    """Generate Bicep table definitions."""
    lines = [
        "// ============================================================",
        "// AUTO-GENERATED — do not edit manually",
        "// Run: python scripts/generate.py",
        "// ============================================================",
        "",
        "@description('Resource ID van de Log Analytics workspace')",
        "param workspaceId string",
        "",
        "resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {",
        "  name: last(split(workspaceId, '/'))",
        "}",
        "",
    ]

    for c in connectors:
        safe_name = c["key"]
        lines.append(f"// {c['name']} — from {c['_source']}")
        lines.append(f"resource table_{safe_name} 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {{")
        lines.append(f"  parent: workspace")
        lines.append(f"  name: '{c['table']}'")
        lines.append(f"  properties: {{")
        lines.append(f"    plan: '{c['plan']}'")
        if c["plan"] == "Analytics":
            lines.append(f"    retentionInDays: {c['retention']}")
        lines.append(f"    totalRetentionInDays: {c['totalRetention']}")
        lines.append(f"    schema: {{")
        lines.append(f"      name: '{c['table']}'")
        lines.append(f"      columns: [")
        lines.append(f"        {{ name: 'TimeGenerated', type: 'datetime' }}")
        for col in c["columns"]:
            lines.append(f"        {{ name: '{col['name']}', type: '{col['type']}' }}")
        lines.append(f"      ]")
        lines.append(f"    }}")
        lines.append(f"  }}")
        lines.append(f"}}")
        lines.append("")

    return "\n".join(lines)


def generate_dcr_bicep(connectors: list[dict]) -> str:
    """Generate Bicep DCR stream declarations and data flows."""
    # Group by DCR
    dcr_groups: dict[str, list[dict]] = {}
    for c in connectors:
        dcr_groups.setdefault(c["dcr"], []).append(c)

    dcr_meta = {
        "daily": {"name_suffix": "daily-scores", "display": "Dagelijkse Scores"},
        "weekly": {"name_suffix": "weekly-snapshots", "display": "Wekelijkse Snapshots"},
        "intune": {"name_suffix": "intune", "display": "Intune Data"},
    }

    lines = [
        "// ============================================================",
        "// AUTO-GENERATED — do not edit manually",
        "// Run: python scripts/generate.py",
        "// ============================================================",
        "",
        "@description('Locatie voor alle resources')",
        "param location string = resourceGroup().location",
        "",
        "@description('Unieke token voor resource namen')",
        "param resourceToken string",
        "",
        "@description('Tags voor alle resources')",
        "param tags object = {}",
        "",
        "@description('Resource ID van de Log Analytics workspace')",
        "param workspaceId string",
        "",
        "@description('Data Collection Endpoint ID')",
        "param dceId string",
        "",
    ]

    output_ids = []

    for dcr_key, group in dcr_groups.items():
        meta = dcr_meta.get(dcr_key, {"name_suffix": dcr_key, "display": dcr_key})
        res_name = f"dcr_{dcr_key}"
        bicep_name = f"dcr-defender-{meta['name_suffix']}-${{resourceToken}}"

        lines.append(f"// {meta['display']}")
        lines.append(f"resource {res_name} 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {{")
        lines.append(f"  name: '{bicep_name}'")
        lines.append(f"  location: location")
        lines.append(f"  tags: tags")
        lines.append(f"  properties: {{")
        lines.append(f"    dataCollectionEndpointId: dceId")

        # Stream declarations
        lines.append(f"    streamDeclarations: {{")
        for c in group:
            stream = f"Custom-{c['table']}"
            lines.append(f"      '{stream}': {{")
            lines.append(f"        columns: [")
            lines.append(f"          {{ name: 'TimeGenerated', type: 'datetime' }}")
            for col in c["columns"]:
                lines.append(f"          {{ name: '{col['name']}', type: '{col['type']}' }}")
            lines.append(f"        ]")
            lines.append(f"      }}")
        lines.append(f"    }}")

        # Destinations
        lines.append(f"    destinations: {{")
        lines.append(f"      logAnalytics: [")
        lines.append(f"        {{")
        lines.append(f"          workspaceResourceId: workspaceId")
        lines.append(f"          name: 'defender-dashboard-workspace'")
        lines.append(f"        }}")
        lines.append(f"      ]")
        lines.append(f"    }}")

        # Data flows
        lines.append(f"    dataFlows: [")
        for c in group:
            stream = f"Custom-{c['table']}"
            lines.append(f"      {{")
            lines.append(f"        streams: [ '{stream}' ]")
            lines.append(f"        destinations: [ 'defender-dashboard-workspace' ]")
            lines.append(f"        transformKql: 'source | extend TimeGenerated = now()'")
            lines.append(f"        outputStream: '{stream}'")
            lines.append(f"      }}")
        lines.append(f"    ]")

        lines.append(f"  }}")
        lines.append(f"}}")
        lines.append("")

        output_ids.append((dcr_key, res_name))

    # Outputs
    for dcr_key, res_name in output_ids:
        camel = dcr_key[0].upper() + dcr_key[1:]
        lines.append(f"@description('DCR {camel} — Immutable ID')")
        lines.append(f"output dcr{camel}ImmutableId string = {res_name}.properties.immutableId")
        lines.append(f"")
        lines.append(f"@description('DCR {camel} — Resource ID')")
        lines.append(f"output dcr{camel}Id string = {res_name}.id")
        lines.append(f"")

    return "\n".join(lines)


def generate_endpoints_json(connectors: list[dict]) -> str:
    """Generate endpoints.json for the Function App."""
    groups: dict[str, list] = {}
    for c in connectors:
        entry = {
            "key": c["key"],
            "url": c["url"],
            "method": "GET",
            "scope": c["scope"],
            "stream": f"Custom-{c['table']}",
            "dcr": c["dcr"],
            "transform": c["transform"],
        }
        groups.setdefault(c["schedule"], []).append(entry)

    return json.dumps(groups, indent=2) + "\n"


def main() -> None:
    print("Loading connectors...")
    connectors = load_connectors()
    print(f"  Found {len(connectors)} connectors")

    INFRA_DIR.mkdir(parents=True, exist_ok=True)

    # Generate workspace tables
    workspace_bicep = generate_workspace_bicep(connectors)
    workspace_path = INFRA_DIR / "tables.bicep"
    workspace_path.write_text(workspace_bicep, encoding="utf-8")
    print(f"  Generated {workspace_path.relative_to(ROOT)}")

    # Generate DCR
    dcr_bicep = generate_dcr_bicep(connectors)
    dcr_path = INFRA_DIR / "dcr.bicep"
    dcr_path.write_text(dcr_bicep, encoding="utf-8")
    print(f"  Generated {dcr_path.relative_to(ROOT)}")

    # Generate endpoints.json
    endpoints_json = generate_endpoints_json(connectors)
    FUNCTION_CONFIG.write_text(endpoints_json, encoding="utf-8")
    print(f"  Generated {FUNCTION_CONFIG.relative_to(ROOT)}")

    print("Done!")


if __name__ == "__main__":
    main()
