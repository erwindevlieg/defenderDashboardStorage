// ============================================================
// main.bicep — Orchestrator voor Defender Dashboard Storage
// ============================================================

targetScope = 'resourceGroup'

@description('Locatie voor alle resources')
param location string = resourceGroup().location

@description('Unieke token voor resource namen (gebruik bijv. een korte hash)')
@minLength(3)
@maxLength(10)
param resourceToken string

@description('Tags voor alle resources')
param tags object = {
  project: 'defender-dashboard'
  managedBy: 'bicep'
}

// --- App Role Bootstrap ---
@description('''
(Optioneel) Resource ID van een bestaande User-Assigned Managed Identity die het deployment script mag uitvoeren.
Deze UAMI moet de Microsoft Graph app role "AppRoleAssignment.ReadWrite.All" hebben.
Als je dit invult, worden de Defender- en Graph API-permissies automatisch toegewezen aan de polling identity.
Formaat: /subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/{naam}
Laat leeg om API-permissies handmatig toe te wijzen (zie docs/bootstrap.md).
''')
param scriptRunnerIdentityId string = ''

// --- Source Control ---
@description('GitHub repository URL voor automatische Function App code-deployment')
param repoUrl string = ''

@description('Branch voor code-deployment')
param repoBranch string = 'main'

// --- Notificaties ---
@description('E-mailadres voor alert notificaties (bijv. bij mislukte data-ingestie)')
param alertEmail string = ''

// --- Retentie ---
@description('Retentie in dagen voor Log Analytics data (standaard 90)')
@minValue(30)
@maxValue(730)
param retentionInDays int = 90

// ============================================================
// Module: Managed Identity
// ============================================================
module identity 'modules/identity.bicep' = {
  name: 'deploy-identity'
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
  }
}

// ============================================================
// Module: Log Analytics Workspace + Tabellen
// ============================================================
module workspace 'modules/workspace.bicep' = {
  name: 'deploy-workspace'
  params: {
    location: location
    workspaceName: 'law-defender-dashboard-${resourceToken}'
    tags: tags
    retentionInDays: retentionInDays
  }
}

// ============================================================
// Module: Data Collection Rules + Endpoint
// ============================================================
module dcr 'modules/dcr.bicep' = {
  name: 'deploy-dcr'
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
    workspaceId: workspace.outputs.workspaceId
  }
}

// ============================================================
// Module: Monitoring (Application Insights + Alerts)
// ============================================================
module monitoring 'modules/monitoring.bicep' = {
  name: 'deploy-monitoring'
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
    workspaceId: workspace.outputs.workspaceId
    alertEmail: alertEmail
  }
}

// ============================================================
// Module: App Configuration
// ============================================================
module appConfig 'modules/app-config.bicep' = {
  name: 'deploy-app-config'
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
    identityPrincipalId: identity.outputs.principalId
  }
}

// ============================================================
// Module: Function App
// ============================================================
module functionApp 'modules/function-app.bicep' = {
  name: 'deploy-function-app'
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
    identityId: identity.outputs.identityId
    identityClientId: identity.outputs.clientId
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    dceEndpoint: dcr.outputs.dceEndpoint
    dcrDailyScoresImmutableId: dcr.outputs.dcrDailyScoresImmutableId
    dcrWeeklySnapshotsImmutableId: dcr.outputs.dcrWeeklySnapshotsImmutableId
    dcrIntuneImmutableId: dcr.outputs.dcrIntuneImmutableId
    appConfigEndpoint: appConfig.outputs.appConfigEndpoint
    repoUrl: repoUrl
    repoBranch: repoBranch
  }
}

// ============================================================
// Module: Workspace RBAC (per-persona + Function App)
// ============================================================
module rbacWorkspace 'modules/rbac-workspace.bicep' = {
  name: 'deploy-rbac-workspace'
  params: {
    workspaceId: workspace.outputs.workspaceId
    functionAppPrincipalId: identity.outputs.principalId
  }
}

// ============================================================
// Module: App Role Assignments (optioneel, vereist bootstrap UAMI)
// ============================================================
module rbacAppRoles 'modules/rbac-approles.bicep' = if (!empty(scriptRunnerIdentityId)) {
  name: 'deploy-rbac-approles'
  params: {
    location: location
    tags: tags
    identityPrincipalId: identity.outputs.principalId
    scriptRunnerIdentityId: scriptRunnerIdentityId
  }
}

// ============================================================
// Module: Workbooks (dashboards auto-deploy)
// ============================================================
module workbooks 'modules/workbooks.bicep' = {
  name: 'deploy-workbooks'
  params: {
    location: location
    workspaceId: workspace.outputs.workspaceId
    tags: tags
  }
}

// ============================================================
// Module: Custom Connectors (voeg hier eigen databronnen toe)
// ============================================================
module custom 'custom/custom.bicep' = {
  name: 'deploy-custom-connectors'
  params: {
    workspaceId: workspace.outputs.workspaceId
    dceId: dcr.outputs.dceId
    location: location
    resourceToken: resourceToken
    tags: tags
  }
}

// ============================================================
// Outputs
// ============================================================
output workspaceName string = workspace.outputs.workspaceName
output workspaceId string = workspace.outputs.workspaceId
output functionAppName string = functionApp.outputs.functionAppName
output functionAppHostName string = functionApp.outputs.functionAppHostName
output dceEndpoint string = dcr.outputs.dceEndpoint
output appConfigEndpoint string = appConfig.outputs.appConfigEndpoint
output identityClientId string = identity.outputs.clientId
output identityPrincipalId string = identity.outputs.principalId
