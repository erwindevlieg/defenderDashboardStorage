// ============================================================
// rbac-workspace.bicep — RBAC voor workspace toegang
// ============================================================

@description('Resource ID of the Log Analytics workspace')
param workspaceId string

@description('Principal ID of the Function App Managed Identity')
param functionAppPrincipalId string

// --- Rol-definitie IDs ---
var monitoringMetricsPublisherRoleId = '3913510d-678f-4e67-9dde-b59c5db8a5b8'

// --- Bestaande workspace ---
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: last(split(workspaceId, '/'))
}

// ============================================================
// Function App MI — Monitoring Metrics Publisher op workspace
// ============================================================
resource functionAppMetricsPublisher 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: workspace
  name: guid(workspace.id, functionAppPrincipalId, monitoringMetricsPublisherRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleId)
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
    description: 'Function App MI: Monitoring Metrics Publisher voor data ingestie'
  }
}
