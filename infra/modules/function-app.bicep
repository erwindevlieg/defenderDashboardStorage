// ============================================================
// function-app.bicep — Azure Function App (Flex Consumption)
// ============================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique token for resource names')
param resourceToken string

@description('Tags applied to all resources')
param tags object = {}

@description('Resource ID of the User-Assigned Managed Identity')
param identityId string

@description('Client ID of the User-Assigned Managed Identity')
param identityClientId string

@description('Application Insights Connection String')
param appInsightsConnectionString string

@description('DCE Endpoint URI')
param dceEndpoint string

@description('DCR Daily Scores Immutable ID')
param dcrDailyScoresImmutableId string

@description('DCR Daily Device — Immutable ID')
param dcrDailyDeviceImmutableId string

@description('DCR Weekly Snapshots Immutable ID')
param dcrWeeklySnapshotsImmutableId string

@description('DCR Intune Immutable ID')
param dcrIntuneImmutableId string

@description('App Configuration endpoint URL')
param appConfigEndpoint string = ''

@description('GitHub repository URL for automatic code deployment (e.g. https://github.com/user/repo)')
param repoUrl string = ''

@description('Branch for code deployment')
param repoBranch string = 'main'

@description('Maximum concurrent endpoint polls per run (default 5)')
@minValue(1)
@maxValue(20)
param pollConcurrency int = 5

@description('Total HTTP timeout in seconds for outbound API calls')
@minValue(30)
@maxValue(600)
param httpTotalTimeoutSecs int = 120

@description('Maximum number of retries on transient HTTP failures (429/5xx)')
@minValue(0)
@maxValue(10)
param httpMaxRetries int = 3

@description('Restrict the /api/health endpoint to a fixed allow-list (recommended in production). Leave false to keep the endpoint anonymous and reachable from anywhere, which keeps the Deploy-to-Azure UX simple.')
param restrictHealthEndpoint bool = false

@description('IPv4 CIDR ranges allowed to call the function app when restrictHealthEndpoint is true.')
param allowedIpRanges array = []

// ============================================================
// Storage Account (for the Function App runtime)
// ============================================================

var ipSecurityRestrictionRules = [for (cidr, idx) in allowedIpRanges: {
  ipAddress: cidr
  action: 'Allow'
  priority: 100 + idx
  name: 'allow-${idx}'
}]
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'stdefenderdash${resourceToken}'
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
  }
}

// ============================================================
// App Service Plan (Flex Consumption)
// ============================================================
resource hostingPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'plan-defender-dashboard-${resourceToken}'
  location: location
  tags: tags
  sku: {
    tier: 'FlexConsumption'
    name: 'FC1'
  }
  kind: 'functionapp'
  properties: {
    reserved: true // Linux
  }
}

// ============================================================
// Function App
// ============================================================
resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: 'func-defender-dashboard-${resourceToken}'
  location: location
  tags: union(tags, { 'azd-service-name': 'function-app' })
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: true
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storageAccount.properties.primaryEndpoints.blob}deploymentpackage'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: identityId
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 2
        instanceMemoryMB: 512
      }
      runtime: {
        name: 'python'
        version: '3.11'
      }
    }
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      ipSecurityRestrictionsDefaultAction: restrictHealthEndpoint ? 'Deny' : 'Allow'
      ipSecurityRestrictions: restrictHealthEndpoint ? ipSecurityRestrictionRules : []
      appSettings: [
        { name: 'AZURE_CLIENT_ID', value: identityClientId }
        { name: 'AzureWebJobsStorage__accountName', value: storageAccount.name }
        { name: 'AzureWebJobsStorage__credential', value: 'managedidentity' }
        { name: 'AzureWebJobsStorage__clientId', value: identityClientId }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
        { name: 'DCE_ENDPOINT', value: dceEndpoint }
        { name: 'DCR_DAILY_SCORES_ID', value: dcrDailyScoresImmutableId }
        { name: 'DCR_DAILY_DEVICE_ID', value: dcrDailyDeviceImmutableId }
        { name: 'DCR_WEEKLY_SNAPSHOTS_ID', value: dcrWeeklySnapshotsImmutableId }
        { name: 'DCR_INTUNE_ID', value: dcrIntuneImmutableId }
        { name: 'APP_CONFIG_ENDPOINT', value: appConfigEndpoint }
        { name: 'STATE_STORAGE_ACCOUNT', value: storageAccount.name }
        { name: 'STATE_TABLE_NAME', value: 'FailedEndpoints' }
        { name: 'INGESTION_STRICT_SCHEMA', value: 'false' }
        { name: 'TOKEN_REFRESH_MARGIN_SECONDS', value: '300' }
        { name: 'FAILED_ENDPOINT_TTL_HOURS', value: '24' }
        { name: 'POLL_CONCURRENCY', value: string(pollConcurrency) }
        { name: 'HTTP_TOTAL_TIMEOUT_SECS', value: string(httpTotalTimeoutSecs) }
        { name: 'HTTP_MAX_RETRIES', value: string(httpMaxRetries) }
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
      ]
    }
  }
}

// Storage Blob Data Owner — UAMI needs access to deployment container
var storageBlobDataOwnerRoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, identityId, storageBlobDataOwnerRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
    principalId: reference(identityId, '2023-01-31').principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Table Data Contributor — UAMI persists failed-endpoint state across cold starts
var storageTableDataContributorRoleId = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
resource storageTableRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, identityId, storageTableDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: reference(identityId, '2023-01-31').principalId
    principalType: 'ServicePrincipal'
  }
}

// Table service + failed-endpoint state table (Flex Consumption is stateless, so we persist)
resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource failedEndpointsTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: 'FailedEndpoints'
}

// ============================================================
// Source Control — automatic code deployment from GitHub
// ============================================================
resource sourceControl 'Microsoft.Web/sites/sourcecontrols@2024-04-01' = if (!empty(repoUrl)) {
  parent: functionApp
  name: 'web'
  properties: {
    repoUrl: repoUrl
    branch: repoBranch
    isManualIntegration: true // no webhook; manual sync only
  }
}

// ============================================================
// Outputs
// ============================================================
@description('Function App name')
output functionAppName string = functionApp.name

@description('Function App resource ID')
output functionAppId string = functionApp.id

@description('Function App default hostname')
output functionAppHostName string = functionApp.properties.defaultHostName
