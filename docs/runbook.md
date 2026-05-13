# Operationeel Runbook — Defender Dashboard Storage

## Dagelijks Monitoring

### Controleer of data binnenkomt

```kusto
// Check meest recente data per tabel
union withsource=TableName
  DefenderExposureScore_CL,
  DefenderSecureScore_CL,
  DefenderConfigurationScore_CL,
  DefenderRecommendations_CL
| summarize LastRecord = max(TimeGenerated) by TableName
| extend HoursAgo = datetime_diff('hour', now(), LastRecord)
| order by HoursAgo desc
```

### Controleer Function App gezondheid

- **Azure Portal:** Function App → Functions → Monitor
- **Application Insights:** Failures blade voor foutanalyse
- **Alert:** `alert-defender-function-failures-*` stuurt notificaties bij >3 failures

---

## Troubleshooting

### Geen data binnenkomt

1. **Controleer Function App logs:**
   ```bash
   az functionapp log tail --name func-defender-dashboard-prod01 --resource-group rg-defender-dashboard
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

### RBAC problemen

- **ABAC niet actief:** Controleer dat workspace Access Control Mode = "Require workspace permissions"
- **Gebruiker ziet alle tabellen:** Zoek naar conflicterende `*/read` rollen (Reader, LA Reader, Monitoring Reader) op hogere scopes

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

4. Deploy infra via GitHub Actions (`infra/` wijziging)

### Via Code (nieuw transform type)

1. Voeg transform logica toe aan `polling/engine.py` → `_transform()`
2. Voeg tests toe aan `tests/test_engine.py`
3. Deploy function app via GitHub Actions

---

## Retentie Wijzigen

Pas per-tabel retentie aan in `infra/modules/workspace.bicep`:

```bicep
properties: {
  retentionInDays: 365      // Interactieve retentie (queries)
  totalRetentionInDays: 1826 // Totaal inclusief archief
}
```

Deploy via `deploy-infra.yml`.

> ⚠️ Bij verkorten van retentie: Azure wacht 30 dagen voordat data daadwerkelijk wordt verwijderd.

---

## Kosten Monitoring

Verwachte kosten (~5.000 apparaten):
- **Log Analytics:** ~€2-6/maand (< 2 GB ingestie)
- **Function App:** ~€0/maand (binnen free tier)
- **App Configuration:** €0/maand (free tier)
- **Application Insights:** Inbegrepen bij LA workspace

Monitor via Azure Cost Management:
```
Resource Group: rg-defender-dashboard
```
