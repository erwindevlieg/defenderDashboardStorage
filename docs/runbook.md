# Operationeel Runbook — Defender Dashboard Storage

## Dagelijks Monitoring

### Controleer of data binnenkomt

```kusto
// Check meest recente data per tabel
union withsource=TableName
  DefenderExposureScore_CL,
  DefenderSecureScore_CL,
  DefenderConfigurationScore_CL,
  DefenderAlertAggregates_CL,
  DefenderRecommendations_CL,
  DefenderDeviceInventory_CL,
  DefenderAVHealth_CL,
  DefenderVulnDelta_CL,
  IntuneDevices_CL
| summarize LastRecord = max(TimeGenerated) by TableName
| extend HoursAgo = datetime_diff('hour', now(), LastRecord)
| extend Status = iff(HoursAgo > 48, '🔴 Verouderd', iff(HoursAgo > 24, '🟡 Aandacht', '🟢 OK'))
| order by HoursAgo desc
```

### Controleer Function App gezondheid

- **Azure Portal:** Function App → Functions → Monitor
- **Application Insights:** Failures blade voor foutanalyse
- **Alert:** `alert-defender-function-failures-*` stuurt e-mail bij >3 failures
- **Alert:** `alert-defender-missing-data-*` stuurt e-mail bij ontbrekende data

---

## Troubleshooting

### Geen data binnenkomt

1. **Controleer Function App logs:**
   ```bash
   az functionapp log tail --name func-defender-dashboard-<token> --resource-group rg-defender-dashboard
   ```

2. **Controleer token propagation:**
   - Na nieuwe app role assignments: wacht tot 1 uur
   - Na downstream cache invalidatie: tot 24 uur

3. **Controleer DCR configuratie:**
   - Ga naar Data Collection Rules in Azure Portal
   - Controleer dat streams en destinations correct zijn

4. **Test API handmatig:**
   ```bash
   TOKEN=$(az account get-access-token --resource https://api.securitycenter.microsoft.com --query accessToken -o tsv)
   curl -H "Authorization: Bearer $TOKEN" https://api.securitycenter.microsoft.com/api/exposureScore
   ```

### Function App timeout

- Flex Consumption standaard timeout: 30 minuten
- Bij grote datasets (>10.000 apparaten): overweeg paginering in batches
- Controleer `host.json` voor `functionTimeout` instelling

### Retry en backfill

De polling engine heeft ingebouwde retry- en backfill-logica:

- **Retry:** 3x exponentieel backoff (2, 4, 8 seconden basis + jitter) bij 429/5xx fouten
- **Backfill:** Gefaalde endpoints worden bij de volgende run opnieuw geprobeerd
- **TTL op backfill:** Mislukte endpoints worden na 24 uur uit de retry-queue verwijderd om eindeloos retryen op permanent kapotte endpoints te voorkomen
- **Niet-retryable:** 400, 401, 403 worden direct overgeslagen (configuratiefout)

### Polling samenvatting per run

Elke run schrijft één samenvattingsregel met `custom_dimensions` voor App Insights:

```kusto
traces
| where message startswith "Polling samenvatting"
| extend
    schedule = tostring(customDimensions.schedule),
    total = toint(customDimensions.total),
    succeeded = toint(customDimensions.succeeded),
    failed = toint(customDimensions.failed),
    empty = toint(customDimensions.empty),
    records = toint(customDimensions.records_total),
    duration_s = todouble(customDimensions.duration_seconds),
    p50 = todouble(customDimensions.duration_p50),
    p95 = todouble(customDimensions.duration_p95),
    failed_keys = tostring(customDimensions.failed_keys)
| project timestamp, schedule, succeeded, failed, empty, records, duration_s, p50, p95, failed_keys
| order by timestamp desc
```

### Schema-validatie

Endpoints met `expected_columns` in hun config worden vóór upload gefilterd op onverwachte kolommen. Default is **lenient**: onbekende kolommen worden weggefilterd en gelogd als waarschuwing. Zet App Setting `INGESTION_STRICT_SCHEMA=true` om elke mismatch hard te laten falen.

```kusto
traces
| where message has "Schema-mismatch"
| order by timestamp desc
```

---

## Nieuwe Endpoint Toevoegen

### Via App Configuration (geen code wijziging)

1. Voeg een nieuw key-value pair toe aan App Configuration:
   ```
   Key: endpoints:daily:newEndpoint
   Value: {"url": "...", "method": "GET", "scope": "...", "stream": "Custom-NewTable_CL", "dcr": "daily", "transform": "list"}
   ```

2. Voeg de corresponderende tabel toe aan `workspace.bicep`

3. Voeg de stream toe aan de juiste DCR in `dcr.bicep`

4. Recompile en deploy:
   ```bash
   az bicep build --file infra/main.bicep --outfile azuredeploy.json
   ```

### Via Code (nieuw transform type)

1. Voeg transform logica toe aan `polling/engine.py` → `_transform()`
2. Voeg tests toe aan `tests/test_engine.py`
3. Deploy function app opnieuw

---

## Retentie Wijzigen

Pas per-tabel retentie aan in `infra/modules/workspace.bicep`:

```bicep
properties: {
  retentionInDays: 365      // Interactieve retentie (queries)
  totalRetentionInDays: 1826 // Totaal inclusief archief
}
```

Of pas de workspace-brede retentie aan via de `retentionInDays` parameter (standaard 90 dagen).

> ⚠️ Bij verkorten van retentie: Azure wacht 30 dagen voordat data daadwerkelijk wordt verwijderd.

---

## Kosten Monitoring

### Verwachte kosten (~5.000 apparaten)

- **Log Analytics:** ~€2-6/maand (< 2 GB ingestie)
- **Function App:** ~€0/maand (binnen free tier)
- **App Configuration:** €0/maand (free tier)
- **Application Insights:** Inbegrepen bij LA workspace

### KQL: Ingestie per tabel (afgelopen 30 dagen)

```kusto
Usage
| where TimeGenerated > ago(30d)
| where DataType endswith "_CL"
| summarize IngestieGB = sum(Quantity) / 1024 by DataType
| extend KostenAnalytics_EUR = round(IngestieGB * 2.76, 2)
| extend KostenBasic_EUR = round(IngestieGB * 0.56, 2)
| order by IngestieGB desc
```

### KQL: Dagelijkse ingestie trend

```kusto
Usage
| where TimeGenerated > ago(30d)
| where DataType endswith "_CL"
| summarize DagGB = sum(Quantity) / 1024 by bin(TimeGenerated, 1d)
| order by TimeGenerated asc
```

### KQL: Maandelijkse kosten schatting

```kusto
Usage
| where TimeGenerated > ago(30d)
| where DataType endswith "_CL"
| summarize TotaalGB = sum(Quantity) / 1024
| extend MaandKosten_EUR = round(TotaalGB * 2.76, 2)
| project TotaalGB = round(TotaalGB, 4), MaandKosten_EUR
```

Monitor ook via Azure Cost Management:
```
Resource Group: rg-defender-dashboard
```
