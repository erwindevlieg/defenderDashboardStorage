// ============================================================
// main.bicep — Orchestrator for Defender Dashboard Storage
// ============================================================

targetScope = 'resourceGroup'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique token for resource names (e.g. a short hash)')
@minLength(3)
@maxLength(10)
param resourceToken string

@description('Tags applied to all resources')
param tags object = {
  project: 'defender-dashboard'
  managedBy: 'bicep'
}

// --- App Role Bootstrap ---
@description('''
(Optional) Resource ID of an existing User-Assigned Managed Identity that may run the deployment script.
This UAMI must hold the Microsoft Graph app role "AppRoleAssignment.ReadWrite.All".
If set, Defender and Graph API permissions are assigned automatically to the polling identity.
Format: /subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/{name}
Leave empty to assign API permissions manually (see the Bootstrap wiki page: https://github.com/erwindevlieg/defenderDashboardStorage/wiki/Bootstrap).
''')
param scriptRunnerIdentityId string = ''

// --- Source Control ---
@description('GitHub repository URL for automatic Function App code deployment')
param repoUrl string = ''

@description('Branch for code deployment')
param repoBranch string = 'main'

// --- Notifications ---
@description('Email address for alert notifications (e.g. failed data ingestion)')
param alertEmail string = ''

// --- Retention ---
@description('Retention in days for Log Analytics data (default 90)')
@minValue(30)
@maxValue(730)
param retentionInDays int = 90

// --- Polling tuning ---
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

// --- Network ---
@description('Restrict the function app to a fixed IP allow-list. Leave false to keep the Deploy-to-Azure experience simple. Enable in production environments that require explicit IP allow-listing.')
param restrictHealthEndpoint bool = false

@description('IPv4 CIDR ranges allowed to call the function app when restrictHealthEndpoint is true.')
param allowedIpRanges array = []

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
    pollConcurrency: pollConcurrency
    httpTotalTimeoutSecs: httpTotalTimeoutSecs
    httpMaxRetries: httpMaxRetries
    restrictHealthEndpoint: restrictHealthEndpoint
    allowedIpRanges: allowedIpRanges
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
// Module: App Role Assignments (optional; requires bootstrap UAMI)
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
    appInsightsId: monitoring.outputs.appInsightsId
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
