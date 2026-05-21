// ============================================================
// workbooks.bicep — Azure Monitor Workbooks (auto-deploy)
// ============================================================

@description('Location for resources')
param location string = resourceGroup().location

@description('Resource ID of the Log Analytics workspace')
param workspaceId string

@description('Resource ID of the Application Insights component (source for the Polling Health workbook)')
param appInsightsId string

@description('Tags applied to resources')
param tags object = {}

// ============================================================
// Management Dashboard
// ============================================================
var managementSerializedData = '{"version":"Notebook/1.0","items":[{"type":1,"content":{"json":"# Defender Dashboard — Management\\n\\nOverview of security KPIs and trends."},"name":"header"},{"type":1,"content":{"json":"## 📊 Data Freshness"},"name":"freshnessHeader"},{"type":3,"content":{"version":"KqlItem/1.0","query":"union withsource=TableName\\n  DefenderExposureScore_CL,\\n  DefenderSecureScore_CL,\\n  DefenderConfigurationScore_CL,\\n  DefenderAlertAggregates_CL,\\n  DefenderRecommendations_CL\\n| summarize LastRecord=max(TimeGenerated) by TableName\\n| extend HoursAgo=datetime_diff(\'hour\', now(), LastRecord)\\n| extend Status=iff(HoursAgo > 48, \'🔴 Stale\', iff(HoursAgo > 24, \'🟡 Attention\', \'🟢 OK\'))\\n| project TableName, LastRecord, HoursAgo, Status\\n| order by HoursAgo desc","size":0,"title":"Data Freshness (Management Tables)","queryType":0,"resourceType":"microsoft.operationalinsights/workspaces","visualization":"table","gridSettings":{"formatters":[{"columnMatch":"Status","formatter":0},{"columnMatch":"HoursAgo","formatter":8,"formatOptions":{"palette":"redGreen","compositeBarSettings":{"labelText":"","columnSettings":[]}}}]}},"name":"freshness"},{"type":3,"content":{"version":"KqlItem/1.0","query":"DefenderExposureScore_CL\\n| summarize Score=avg(ExposureScore) by bin(TimeGenerated, 1d)\\n| order by TimeGenerated asc","size":0,"title":"Exposure Score Trend","timeContext":{"durationMs":2592000000},"queryType":0,"resourceType":"microsoft.operationalinsights/workspaces","visualization":"linechart","chartSettings":{"yAxis":["Score"],"ySettings":{"min":0,"max":100}}},"name":"exposureScoreTrend"},{"type":3,"content":{"version":"KqlItem/1.0","query":"DefenderSecureScore_CL\\n| summarize Score=avg(CurrentScore), MaxScore=avg(MaxScore) by bin(TimeGenerated, 1d)\\n| order by TimeGenerated asc","size":0,"title":"Secure Score Trend","timeContext":{"durationMs":2592000000},"queryType":0,"resourceType":"microsoft.operationalinsights/workspaces","visualization":"linechart"},"name":"secureScoreTrend"},{"type":3,"content":{"version":"KqlItem/1.0","query":"DefenderConfigurationScore_CL\\n| summarize Score=avg(ConfigurationScore) by bin(TimeGenerated, 1d)\\n| order by TimeGenerated asc","size":0,"title":"Configuration Score Trend","timeContext":{"durationMs":2592000000},"queryType":0,"resourceType":"microsoft.operationalinsights/workspaces","visualization":"linechart"},"name":"configScoreTrend"},{"type":3,"content":{"version":"KqlItem/1.0","query":"DefenderAlertAggregates_CL\\n| summarize AvgMTTR=avg(MTTR_Hours), AvgMTTD=avg(MTTD_Hours) by bin(TimeGenerated, 1d)\\n| order by TimeGenerated asc","size":0,"title":"MTTR / MTTD Trend (hours)","timeContext":{"durationMs":2592000000},"queryType":0,"resourceType":"microsoft.operationalinsights/workspaces","visualization":"linechart"},"name":"mttrMttdTrend"},{"type":3,"content":{"version":"KqlItem/1.0","query":"DefenderAlertAggregates_CL\\n| top 1 by TimeGenerated\\n| project TotalAlerts, HighSeverity, MediumSeverity, LowSeverity","size":4,"title":"Latest Alert Distribution","queryType":0,"resourceType":"microsoft.operationalinsights/workspaces","visualization":"tiles","tileSettings":{"titleContent":{"columnMatch":"Column1"},"showBorder":true}},"name":"alertSummary"},{"type":3,"content":{"version":"KqlItem/1.0","query":"DefenderRecommendations_CL\\n| where TimeGenerated > ago(1d)\\n| summarize Count=count() by Severity\\n| order by Count desc","size":0,"title":"Open Recommendations by Severity","queryType":0,"resourceType":"microsoft.operationalinsights/workspaces","visualization":"piechart"},"name":"recommendationsBySeverity"}],"fallbackResourceIds":[""]}'

resource managementWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid('management-dashboard', resourceGroup().id)
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'Defender Dashboard — Management'
    category: 'workbook'
    sourceId: workspaceId
    serializedData: managementSerializedData
    version: '1.0'
  }
}

// ============================================================
// Device Dashboard
// ============================================================
var deviceSerializedData = '{"version":"Notebook/1.0","items":[{"type":1,"content":{"json":"# Defender Dashboard — Device\\n\\nOperational overview of devices, software and compliance."},"name":"header"},{"type":1,"content":{"json":"## 📊 Data Freshness"},"name":"freshnessHeader"},{"type":3,"content":{"version":"KqlItem/1.0","query":"union withsource=TableName\\n  DefenderDeviceInventory_CL,\\n  DefenderAVHealth_CL,\\n  DefenderVulnDelta_CL,\\n  DefenderSoftwareInventory_CL,\\n  DefenderSecureConfig_CL,\\n  DefenderDeviceSoftware_CL,\\n  IntuneDevices_CL,\\n  IntuneDetectedApps_CL,\\n  IntuneComplianceReports_CL\\n| summarize LastRecord=max(TimeGenerated) by TableName\\n| extend HoursAgo=datetime_diff(\'hour\', now(), LastRecord)\\n| extend Status=iff(HoursAgo > 192, \'🔴 Stale\', iff(HoursAgo > 168, \'🟡 Attention\', \'🟢 OK\'))\\n| project TableName, LastRecord, HoursAgo, Status\\n| order by HoursAgo desc","size":0,"title":"Data Freshness (Device Tables)","queryType":0,"resourceType":"microsoft.operationalinsights/workspaces","visualization":"table","gridSettings":{"formatters":[{"columnMatch":"Status","formatter":0},{"columnMatch":"HoursAgo","formatter":8,"formatOptions":{"palette":"redGreen","compositeBarSettings":{"labelText":"","columnSettings":[]}}}]}},"name":"freshness"},{"type":3,"content":{"version":"KqlItem/1.0","query":"DefenderDeviceInventory_CL\\n| where TimeGenerated > ago(7d)\\n| summarize arg_max(TimeGenerated, *) by DeviceId\\n| summarize Count=count() by RiskScore\\n| order by Count desc","size":0,"title":"Devices by Risk Score","queryType":0,"resourceType":"microsoft.operationalinsights/workspaces","visualization":"piechart"},"name":"devicesByRisk"},{"type":3,"content":{"version":"KqlItem/1.0","query":"DefenderDeviceInventory_CL\\n| where TimeGenerated > ago(7d)\\n| summarize arg_max(TimeGenerated, *) by DeviceId\\n| summarize Count=count() by HealthStatus\\n| order by Count desc","size":0,"title":"Devices by Health Status","queryType":0,"resourceType":"microsoft.operationalinsights/workspaces","visualization":"piechart"},"name":"devicesByHealth"},{"type":3,"content":{"version":"KqlItem/1.0","query":"DefenderDeviceInventory_CL\\n| where TimeGenerated > ago(7d)\\n| summarize arg_max(TimeGenerated, *) by DeviceId\\n| summarize Count=count() by OsPlatform\\n| order by Count desc","size":0,"title":"Devices by OS Platform","queryType":0,"resourceType":"microsoft.operationalinsights/workspaces","visualization":"barchart"},"name":"devicesByOS"},{"type":3,"content":{"version":"KqlItem/1.0","query":"DefenderAVHealth_CL\\n| where TimeGenerated > ago(7d)\\n| summarize arg_max(TimeGenerated, *) by DeviceId\\n| extend SignatureAge = datetime_diff(\'day\', now(), AVSignatureUpdateTime)\\n| summarize Outdated=countif(SignatureAge > 7), Current=countif(SignatureAge <= 7)","size":4,"title":"AV Signature Status","queryType":0,"resourceType":"microsoft.operationalinsights/workspaces","visualization":"tiles"},"name":"avHealth"},{"type":3,"content":{"version":"KqlItem/1.0","query":"IntuneDevices_CL\\n| where TimeGenerated > ago(7d)\\n| summarize arg_max(TimeGenerated, *) by DeviceId\\n| summarize Count=count() by ComplianceState\\n| order by Count desc","size":0,"title":"Intune Compliance Status","queryType":0,"resourceType":"microsoft.operationalinsights/workspaces","visualization":"piechart"},"name":"intuneCompliance"},{"type":3,"content":{"version":"KqlItem/1.0","query":"DefenderSoftwareInventory_CL\\n| where TimeGenerated > ago(7d)\\n| summarize arg_max(TimeGenerated, *) by SoftwareId\\n| where NumberOfWeaknesses > 0\\n| top 20 by NumberOfWeaknesses desc\\n| project SoftwareName, SoftwareVendor, NumberOfWeaknesses, NumberOfDevices, EndOfSupportStatus","size":0,"title":"Top 20 Software with Vulnerabilities","queryType":0,"resourceType":"microsoft.operationalinsights/workspaces","visualization":"table"},"name":"topVulnSoftware"},{"type":3,"content":{"version":"KqlItem/1.0","query":"DefenderSecureConfig_CL\\n| where TimeGenerated > ago(7d)\\n| summarize arg_max(TimeGenerated, *) by DeviceId, ConfigurationId\\n| where IsApplicable == true\\n| summarize Compliant=countif(IsCompliant == true), NonCompliant=countif(IsCompliant == false) by ConfigurationCategory","size":0,"title":"Configuration Compliance by Category","queryType":0,"resourceType":"microsoft.operationalinsights/workspaces","visualization":"barchart","chartSettings":{"seriesLabelSettings":[{"seriesName":"Compliant","color":"green"},{"seriesName":"NonCompliant","color":"red"}]}},"name":"configCompliance"},{"type":3,"content":{"version":"KqlItem/1.0","query":"DefenderVulnDelta_CL\\n| where TimeGenerated > ago(30d)\\n| summarize NewVulns=countif(EventType == \'New\'), FixedVulns=countif(EventType == \'Fixed\') by bin(TimeGenerated, 1d)\\n| order by TimeGenerated asc","size":0,"title":"Vulnerability Delta Trend (30 days)","queryType":0,"resourceType":"microsoft.operationalinsights/workspaces","visualization":"linechart"},"name":"vulnDeltaTrend"}],"fallbackResourceIds":[""]}'

resource deviceWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  // Keep the guid seed unchanged to avoid recreating existing workbooks on upgrade.
  name: guid('werkplek-dashboard', resourceGroup().id)
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'Defender Dashboard — Device'
    category: 'workbook'
    sourceId: workspaceId
    serializedData: deviceSerializedData
    version: '1.0'
  }
}

// ============================================================
// Polling Health Dashboard (Application Insights-bound)
// ============================================================
// Surfaces the operational KPIs that PollingEngine emits as
// ``Polling summary`` traces + poison events. Source is Application
// Insights because that is where ``traces`` / ``exceptions`` live.
var pollingHealthSerializedData = '{"version":"Notebook/1.0","items":[{"type":1,"content":{"json":"# Defender Dashboard — Polling Health\\n\\nOperational health of the Defender/Intune polling pipeline. Source: Application Insights."},"name":"header"},{"type":3,"content":{"version":"KqlItem/1.0","query":"traces\\n| where timestamp > ago(24h) and message startswith \\"Polling summary\\"\\n| extend schedule = tostring(customDimensions.schedule),\\n         ok = toint(customDimensions.succeeded),\\n         failed = toint(customDimensions.failed),\\n         records = tolong(customDimensions.records_total),\\n         dur = toreal(customDimensions.duration_seconds)\\n| summarize Runs=count(), OK=sum(ok), Failed=sum(failed), Records=sum(records), AvgDuration=round(avg(dur),1) by schedule\\n| order by schedule asc","size":0,"title":"Polling runs by schedule (24h)","queryType":0,"resourceType":"microsoft.insights/components","visualization":"table"},"name":"runs24h"},{"type":3,"content":{"version":"KqlItem/1.0","query":"traces\\n| where timestamp > ago(7d) and message startswith \\"Polling summary\\"\\n| extend schedule = tostring(customDimensions.schedule),\\n         p50 = toreal(customDimensions.duration_p50),\\n         p95 = toreal(customDimensions.duration_p95)\\n| summarize P50=avg(p50), P95=avg(p95) by bin(timestamp, 1h), schedule\\n| order by timestamp asc","size":0,"title":"Endpoint duration p50 / p95 (7d, seconds)","timeContext":{"durationMs":604800000},"queryType":0,"resourceType":"microsoft.insights/components","visualization":"linechart"},"name":"durationTrend"},{"type":3,"content":{"version":"KqlItem/1.0","query":"traces\\n| where timestamp > ago(7d) and message startswith \\"Polling summary\\"\\n| extend schedule = tostring(customDimensions.schedule),\\n         records = tolong(customDimensions.records_total)\\n| summarize Records=sum(records) by bin(timestamp, 1d), schedule\\n| order by timestamp asc","size":0,"title":"Records ingested per day (7d)","timeContext":{"durationMs":604800000},"queryType":0,"resourceType":"microsoft.insights/components","visualization":"barchart"},"name":"recordsTrend"},{"type":3,"content":{"version":"KqlItem/1.0","query":"traces\\n| where timestamp > ago(24h) and message startswith \\"Polling summary\\"\\n| extend schedule = tostring(customDimensions.schedule),\\n         failed_keys = tostring(customDimensions.failed_keys),\\n         failed_count = toint(customDimensions.failed)\\n| where failed_count > 0\\n| project timestamp, schedule, failed_count, failed_keys\\n| order by timestamp desc","size":0,"title":"Recently failed endpoints (24h)","queryType":0,"resourceType":"microsoft.insights/components","visualization":"table"},"name":"recentFailures"},{"type":3,"content":{"version":"KqlItem/1.0","query":"traces\\n| where timestamp > ago(7d) and message has \\"defender.endpoint.poisoned\\"\\n| extend schedule = tostring(customDimensions.schedule),\\n         endpoint = tostring(customDimensions.endpoint_key),\\n         attempts = toint(customDimensions.attempt_count)\\n| project timestamp, schedule, endpoint, attempts\\n| order by timestamp desc","size":0,"title":"Poisoned endpoints (7d)","queryType":0,"resourceType":"microsoft.insights/components","visualization":"table"},"name":"poisoned"}],"fallbackResourceIds":[""]}'

resource pollingHealthWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid('polling-health-dashboard', resourceGroup().id)
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'Defender Dashboard — Polling Health'
    category: 'workbook'
    sourceId: appInsightsId
    serializedData: pollingHealthSerializedData
    version: '1.0'
  }
}


