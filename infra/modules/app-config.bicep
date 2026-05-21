// ============================================================
// app-config.bicep — Azure App Configuration
// ============================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique token for resource names')
param resourceToken string

@description('Tags applied to all resources')
param tags object = {}

@description('Principal ID of the Managed Identity (for RBAC)')
param identityPrincipalId string

// ============================================================
// App Configuration Store
// ============================================================
resource appConfig 'Microsoft.AppConfiguration/configurationStores@2023-03-01' = {
  name: 'appcs-defender-dashboard-${resourceToken}'
  location: location
  tags: tags
  sku: { name: 'free' }
  properties: {
    // Local auth must remain enabled so the ARM `keyValues` child resources can
    // seed endpoint definitions during deployment. Runtime access from the
    // Function App is Entra-only via the App Configuration Data Reader role
    // assignment below — the Function App never uses access keys.
    disableLocalAuth: false
  }
}

// App Configuration Data Reader voor UAMI
var appConfigDataReaderRoleId = '516239f1-63e1-4d78-a4de-a74fb236a071'
resource appConfigRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appConfig.id, identityPrincipalId, appConfigDataReaderRoleId)
  scope: appConfig
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', appConfigDataReaderRoleId)
    principalId: identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================
// Endpoint Configuratie — Dagelijkse Polls
// ============================================================
resource kvExposureScore 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'endpoints:daily:exposureScore'
  properties: {
    value: '{"url": "https://api.securitycenter.microsoft.com/api/exposureScore", "method": "GET", "scope": "https://api.securitycenter.microsoft.com/.default", "stream": "Custom-DefenderExposureScore_CL", "dcr": "daily", "transform": "single"}'
    contentType: 'application/json'
  }
}

resource kvConfigScore 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'endpoints:daily:configurationScore'
  properties: {
    value: '{"url": "https://api.securitycenter.microsoft.com/api/configurationScore", "method": "GET", "scope": "https://api.securitycenter.microsoft.com/.default", "stream": "Custom-DefenderConfigurationScore_CL", "dcr": "daily", "transform": "single"}'
    contentType: 'application/json'
  }
}

resource kvSecureScore 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'endpoints:daily:secureScore'
  properties: {
    value: '{"url": "https://graph.microsoft.com/v1.0/security/secureScores?$top=1", "method": "GET", "scope": "https://graph.microsoft.com/.default", "stream": "Custom-DefenderSecureScore_CL", "dcr": "daily", "transform": "graphList"}'
    contentType: 'application/json'
  }
}

resource kvRecommendations 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'endpoints:daily:recommendations'
  properties: {
    value: '{"url": "https://api.securitycenter.microsoft.com/api/recommendations", "method": "GET", "scope": "https://api.securitycenter.microsoft.com/.default", "stream": "Custom-DefenderRecommendations_CL", "dcr": "daily", "transform": "list"}'
    contentType: 'application/json'
  }
}

resource kvVulnDelta 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'endpoints:daily:vulnDelta'
  properties: {
    value: '{"url": "https://api.securitycenter.microsoft.com/api/machines/SoftwareVulnerabilityChangesByMachine", "method": "GET", "scope": "https://api.securitycenter.microsoft.com/.default", "stream": "Custom-DefenderVulnDelta_CL", "dcr": "daily", "transform": "list"}'
    contentType: 'application/json'
  }
}

// ============================================================
// Endpoint Configuratie — Wekelijkse Polls
// ============================================================
resource kvDeviceInventory 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'endpoints:weekly:deviceInventory'
  properties: {
    value: '{"url": "https://api.securitycenter.microsoft.com/api/machines", "method": "GET", "scope": "https://api.securitycenter.microsoft.com/.default", "stream": "Custom-DefenderDeviceInventory_CL", "dcr": "weekly", "transform": "list"}'
    contentType: 'application/json'
  }
}

resource kvSoftwareInventory 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'endpoints:weekly:softwareInventory'
  properties: {
    value: '{"url": "https://api.securitycenter.microsoft.com/api/Software", "method": "GET", "scope": "https://api.securitycenter.microsoft.com/.default", "stream": "Custom-DefenderSoftwareInventory_CL", "dcr": "weekly", "transform": "list"}'
    contentType: 'application/json'
  }
}

resource kvAVHealth 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'endpoints:weekly:avHealth'
  properties: {
    value: '{"url": "https://api.securitycenter.microsoft.com/api/deviceavstatus", "method": "GET", "scope": "https://api.securitycenter.microsoft.com/.default", "stream": "Custom-DefenderAVHealth_CL", "dcr": "weekly", "transform": "exportList"}'
    contentType: 'application/json'
  }
}

resource kvSecureConfig 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'endpoints:weekly:secureConfig'
  properties: {
    value: '{"url": "https://api.securitycenter.microsoft.com/api/machines/SecureConfigurationsAssessmentByMachine", "method": "GET", "scope": "https://api.securitycenter.microsoft.com/.default", "stream": "Custom-DefenderSecureConfig_CL", "dcr": "weekly", "transform": "exportList"}'
    contentType: 'application/json'
  }
}

// ============================================================
// Endpoint Configuratie — Intune (wekelijks)
// ============================================================
resource kvIntuneDevices 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'endpoints:weekly:intuneDevices'
  properties: {
    value: '{"url": "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices", "method": "GET", "scope": "https://graph.microsoft.com/.default", "stream": "Custom-IntuneDevices_CL", "dcr": "intune", "transform": "graphList"}'
    contentType: 'application/json'
  }
}

resource kvIntuneApps 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfig
  name: 'endpoints:weekly:intuneDetectedApps'
  properties: {
    value: '{"url": "https://graph.microsoft.com/v1.0/deviceManagement/detectedApps", "method": "GET", "scope": "https://graph.microsoft.com/.default", "stream": "Custom-IntuneDetectedApps_CL", "dcr": "intune", "transform": "graphList"}'
    contentType: 'application/json'
  }
}

// ============================================================
// Outputs
// ============================================================
@description('App Configuration endpoint URL')
output appConfigEndpoint string = appConfig.properties.endpoint

@description('App Configuration name')
output appConfigName string = appConfig.name
