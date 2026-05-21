// ============================================================
// monitoring.bicep — Application Insights + Alert Rules
// ============================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique token for resource names')
param resourceToken string

@description('Tags applied to all resources')
param tags object = {}

@description('Resource ID of the Log Analytics workspace')
param workspaceId string

@description('Email address for alert notifications (optional, empty string = no email)')
param alertEmail string = ''

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
// Action Group — alert notifications
// ============================================================
resource actionGroup 'Microsoft.Insights/actionGroups@2023-09-01-preview' = if (!empty(alertEmail)) {
  name: 'ag-defender-dashboard-${resourceToken}'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'DefDashboard'
    enabled: true
    emailReceivers: [
      {
        name: 'admin'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
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
    description: 'More than 3 function failures in the last 30 minutes.'
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
    actions: !empty(alertEmail) ? {
      actionGroups: [ actionGroup.id ]
    } : {}
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
    displayName: 'Defender Dashboard — Missing daily data'
    description: 'No Exposure Score data ingested in the last 26 hours.'
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
    actions: !empty(alertEmail) ? {
      actionGroups: [ actionGroup.id ]
    } : {}
  }
}

// ============================================================
// Alert: Polling run failure rate > 25%
// ============================================================
// Uses the structured "Polling summary" log emitted by PollingEngine._process_endpoints.
// customDimensions.failed and .total drive the ratio.
resource alertHighFailureRate 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-defender-high-failure-rate-${resourceToken}'
  location: location
  tags: tags
  properties: {
    displayName: 'Defender Dashboard — High polling failure rate'
    description: 'More than 25% of endpoints failed in the last polling summary (1h window).'
    severity: 1 // Error
    enabled: true
    evaluationFrequency: 'PT15M'
    windowSize: 'PT1H'
    scopes: [ appInsights.id ]
    criteria: {
      allOf: [
        {
          query: '''traces
| where message startswith "Polling summary"
| extend total = toint(customDimensions.total), failed = toint(customDimensions.failed)
| where total > 0
| extend rate = todouble(failed) / todouble(total)
| where rate > 0.25
| summarize Count = count() by bin(timestamp, 15m)'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: !empty(alertEmail) ? {
      actionGroups: [ actionGroup.id ]
    } : {}
  }
}

// ============================================================
// Alert: Polling run duration > 10 minutes
// ============================================================
resource alertLongRunDuration 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-defender-long-run-duration-${resourceToken}'
  location: location
  tags: tags
  properties: {
    displayName: 'Defender Dashboard — Polling run duration > 10 min'
    description: 'A polling run took longer than 600 seconds (possible API degradation or upstream slowdown).'
    severity: 2 // Warning
    enabled: true
    evaluationFrequency: 'PT30M'
    windowSize: 'PT1H'
    scopes: [ appInsights.id ]
    criteria: {
      allOf: [
        {
          query: '''traces
| where message startswith "Polling summary"
| extend duration_seconds = todouble(customDimensions.duration_seconds)
| where duration_seconds > 600
| summarize Count = count() by bin(timestamp, 30m)'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: !empty(alertEmail) ? {
      actionGroups: [ actionGroup.id ]
    } : {}
  }
}

// ============================================================
// Alert: Endpoint poisoned (B3 signal)
// ============================================================
// Fires when PollingEngine logs ``defender.endpoint.poisoned`` for an
// endpoint that exceeded MAX_POISON_ATTEMPTS. One occurrence is enough
// because the endpoint has stopped being retried — manual triage required.
resource alertEndpointPoisoned 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-defender-endpoint-poisoned-${resourceToken}'
  location: location
  tags: tags
  properties: {
    displayName: 'Defender Dashboard — Endpoint poisoned'
    description: 'An endpoint exceeded the poison threshold and is no longer being retried; manual investigation required.'
    severity: 2 // Warning
    enabled: true
    evaluationFrequency: 'PT15M'
    windowSize: 'PT1H'
    scopes: [ appInsights.id ]
    criteria: {
      allOf: [
        {
          query: '''traces
| where message has "defender.endpoint.poisoned"
| summarize Count = count() by bin(timestamp, 15m)'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: !empty(alertEmail) ? {
      actionGroups: [ actionGroup.id ]
    } : {}
  }
}

// ============================================================
// Alert: App Configuration unreachable
// ============================================================
// If the endpoint catalogue cannot be loaded the polling run silently
// becomes a no-op. Catch any exception originating from the App Config
// client so we get told instead of seeing empty dashboards next morning.
resource alertAppConfigUnreachable 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-defender-appconfig-unreachable-${resourceToken}'
  location: location
  tags: tags
  properties: {
    displayName: 'Defender Dashboard — App Configuration unreachable'
    description: 'Polling could not reach Azure App Configuration in the last 30 minutes; endpoint catalogue may be stale.'
    severity: 1 // Error
    enabled: true
    evaluationFrequency: 'PT15M'
    windowSize: 'PT30M'
    scopes: [ appInsights.id ]
    criteria: {
      allOf: [
        {
          query: '''exceptions
| where outerType has "AppConfiguration" or assembly has "appconfiguration"
   or innermostMessage has "azconfig.io" or innermostMessage has ".azconfig."
| summarize Count = count() by bin(timestamp, 15m)'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: !empty(alertEmail) ? {
      actionGroups: [ actionGroup.id ]
    } : {}
  }
}

// ============================================================
// Alert: Storage Table retries exhausted (A5 signal)
// ============================================================
// state_store._with_retry logs ``Table op X exhausted retries`` when the
// retry budget is spent. Without this alert we silently drift back to the
// in-memory fallback, losing failed-endpoint persistence across cold starts.
resource alertStateTableExhausted 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-defender-state-table-exhausted-${resourceToken}'
  location: location
  tags: tags
  properties: {
    displayName: 'Defender Dashboard — Storage Table retries exhausted'
    description: 'Retry-state Table operations exceeded their retry budget; failed-endpoint persistence may be degraded.'
    severity: 2 // Warning
    enabled: true
    evaluationFrequency: 'PT15M'
    windowSize: 'PT30M'
    scopes: [ appInsights.id ]
    criteria: {
      allOf: [
        {
          query: '''traces
| where message has "exhausted retries"
| summarize Count = count() by bin(timestamp, 15m)'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: !empty(alertEmail) ? {
      actionGroups: [ actionGroup.id ]
    } : {}
  }
}

// ============================================================
// Alert: DCR ingestion uploads failing
// ============================================================
// Catches the "Upload failed for stream X" log line emitted by
// IngestionClient.upload when the Logs Ingestion API rejects a batch.
resource alertIngestionFailures 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-defender-ingestion-failures-${resourceToken}'
  location: location
  tags: tags
  properties: {
    displayName: 'Defender Dashboard — DCR ingestion failures'
    description: 'More than 5 DCR upload failures in the last hour; data is not reaching Log Analytics.'
    severity: 1 // Error
    enabled: true
    evaluationFrequency: 'PT15M'
    windowSize: 'PT1H'
    scopes: [ appInsights.id ]
    criteria: {
      allOf: [
        {
          query: '''traces
| where message startswith "Upload failed for stream"
| summarize Count = count() by bin(timestamp, 15m)'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 5
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: !empty(alertEmail) ? {
      actionGroups: [ actionGroup.id ]
    } : {}
  }
}

// ============================================================
// Outputs
// ============================================================
@description('Application Insights Connection String')
output appInsightsConnectionString string = appInsights.properties.ConnectionString

@description('Application Insights Instrumentation Key')
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey

@description('Application Insights name')
output appInsightsName string = appInsights.name
