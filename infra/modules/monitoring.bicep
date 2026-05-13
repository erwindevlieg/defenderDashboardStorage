// ============================================================
// monitoring.bicep — Application Insights + Alert Rules
// ============================================================

@description('Locatie voor alle resources')
param location string = resourceGroup().location

@description('Unieke token voor resource namen')
param resourceToken string

@description('Tags voor alle resources')
param tags object = {}

@description('Resource ID van de Log Analytics workspace')
param workspaceId string

// ============================================================
// Application Insights
// ============================================================
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-defender-dashboard-${resourceToken}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspaceId
    DisableLocalAuth: true
  }
}

// ============================================================
// Alert: Function App failures
// ============================================================
resource alertFunctionFailures 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-defender-function-failures-${resourceToken}'
  location: location
  tags: tags
  properties: {
    displayName: 'Defender Dashboard — Function Failures'
    description: 'Meer dan 3 function failures in de afgelopen 30 minuten'
    severity: 2 // Warning
    enabled: true
    evaluationFrequency: 'PT15M'
    windowSize: 'PT30M'
    scopes: [ appInsights.id ]
    criteria: {
      allOf: [
        {
          query: 'requests | where success == false | summarize FailedCount = count() by bin(timestamp, 15m)'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 3
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
  }
}

// ============================================================
// Alert: Missing daily data
// ============================================================
resource alertMissingDailyData 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-defender-missing-daily-data-${resourceToken}'
  location: location
  tags: tags
  properties: {
    displayName: 'Defender Dashboard — Ontbrekende dagelijkse data'
    description: 'Geen Exposure Score data ingekomen in de afgelopen 26 uur'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1H'
    windowSize: 'PT1H'
    scopes: [ workspaceId ]
    criteria: {
      allOf: [
        {
          query: 'DefenderExposureScore_CL | where TimeGenerated > ago(26h) | summarize RecordCount = count()'
          timeAggregation: 'Count'
          operator: 'LessThan'
          threshold: 1
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
  }
}

// ============================================================
// Outputs
// ============================================================
@description('Application Insights Connection String')
output appInsightsConnectionString string = appInsights.properties.ConnectionString

@description('Application Insights Instrumentation Key')
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey

@description('Application Insights naam')
output appInsightsName string = appInsights.name
