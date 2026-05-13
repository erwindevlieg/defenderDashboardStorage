// ============================================================
// function-app.bicep — Azure Function App (Flex Consumption)
// ============================================================

@description('Locatie voor alle resources')
param location string = resourceGroup().location

@description('Unieke token voor resource namen')
param resourceToken string

@description('Tags voor alle resources')
param tags object = {}

@description('Resource ID van de User-Assigned Managed Identity')
param identityId string

@description('Client ID van de User-Assigned Managed Identity')
param identityClientId string

@description('Application Insights Connection String')
param appInsightsConnectionString string

@description('DCE Endpoint URI')
param dceEndpoint string

@description('DCR Daily Scores Immutable ID')
param dcrDailyScoresImmutableId string

@description('DCR Weekly Snapshots Immutable ID')
param dcrWeeklySnapshotsImmutableId string

@description('DCR Intune Immutable ID')
param dcrIntuneImmutableId string

@description('App Configuration Endpoint')
param appConfigEndpoint string = ''

@description('GitHub repository URL voor automatische code-deployment (bijv. https://github.com/user/repo)')
param repoUrl string = ''

@description('Branch voor code-deployment')
param repoBranch string = 'main'

// ============================================================
// Storage Account (voor Function App runtime)
// ============================================================
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
      appSettings: [
        { name: 'AZURE_CLIENT_ID', value: identityClientId }
        { name: 'AzureWebJobsStorage__accountName', value: storageAccount.name }
        { name: 'AzureWebJobsStorage__credential', value: 'managedidentity' }
        { name: 'AzureWebJobsStorage__clientId', value: identityClientId }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
        { name: 'DCE_ENDPOINT', value: dceEndpoint }
        { name: 'DCR_DAILY_SCORES_ID', value: dcrDailyScoresImmutableId }
        { name: 'DCR_WEEKLY_SNAPSHOTS_ID', value: dcrWeeklySnapshotsImmutableId }
        { name: 'DCR_INTUNE_ID', value: dcrIntuneImmutableId }
        { name: 'APP_CONFIG_ENDPOINT', value: appConfigEndpoint }
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

// ============================================================
// Source Control — automatische code-deployment vanuit GitHub
// ============================================================
resource sourceControl 'Microsoft.Web/sites/sourcecontrols@2024-04-01' = if (!empty(repoUrl)) {
  parent: functionApp
  name: 'web'
  properties: {
    repoUrl: repoUrl
    branch: repoBranch
    isManualIntegration: true // geen webhook, handmatig sync
  }
}

// ============================================================
// Outputs
// ============================================================
@description('Function App naam')
output functionAppName string = functionApp.name

@description('Function App resource ID')
output functionAppId string = functionApp.id

@description('Function App default hostname')
output functionAppHostName string = functionApp.properties.defaultHostName
