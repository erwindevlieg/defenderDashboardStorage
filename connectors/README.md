# Connector Manifest Format
#
# Each YAML file in this directory defines a data connector.
# Run `python scripts/generate.py` to regenerate Bicep and endpoints.json.
#
# Required fields:
#   key:        Unique identifier (used in App Configuration keys)
#   name:       Human-readable name
#   table:      Log Analytics custom table name (must end in _CL)
#   schedule:   'daily' or 'weekly'
#   dcr:        DCR group: 'daily', 'weekly', or 'intune'
#   url:        API endpoint URL
#   scope:      OAuth2 token scope
#   transform:  Response transform: 'single', 'list', 'graphList', 'exportList'
#   plan:       Table plan: 'Analytics' or 'Basic'
#   retention:  Interactive retention in days (Analytics only, ignored for Basic)
#   totalRetention: Total retention in days
#   columns:    List of column definitions (name + type)
#
# Column types: string, int, real, datetime, boolean, dynamic
# TimeGenerated is added automatically — do not include it.
#
# See existing connectors for examples.
