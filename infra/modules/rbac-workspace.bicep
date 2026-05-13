// ============================================================
// rbac-workspace.bicep — Per-persona RBAC met ABAC-condities
// ============================================================

@description('Resource ID van de Log Analytics workspace')
param workspaceId string

@description('Object ID van sg-defender-dashboard-management (optioneel, lege string = skip)')
param managementGroupObjectId string = ''

@description('Object ID van sg-defender-dashboard-werkplek (optioneel)')
param werkplekGroupObjectId string = ''

@description('Object ID van sg-defender-dashboard-security (optioneel)')
param securityGroupObjectId string = ''

@description('Principal ID van de Function App Managed Identity')
param functionAppPrincipalId string

// --- Rol-definitie IDs ---
var logAnalyticsDataReaderRoleId = '3b03c2da-16b3-4a49-8834-0f8130efdd3b'
var workbookReaderRoleId = 'b279062a-9be3-42a0-92ae-8b3cf002ec4d'
var workbookContributorRoleId = 'e8ddcd69-c73f-4f9f-9844-4100522f16ad'
var monitoringMetricsPublisherRoleId = '3913510d-678f-4e67-9dde-b59c5db8a5b8'

// --- Bestaande workspace ---
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: last(split(workspaceId, '/'))
}

// ============================================================
// Function App MI — Monitoring Metrics Publisher op DCR
// (DCR-scope role assignment zit in dcr.bicep als die apart is,
//  maar voor workspace-level metrics publisher)
// ============================================================

// ============================================================
// MANAGEMENT — Alleen score/KPI-tabellen
// ============================================================
var managementTableCondition = '''(
  (
    !(ActionMatches{'Microsoft.OperationalInsights/workspaces/tables/data/read'})
  )
  OR
  (
    @Resource[Microsoft.OperationalInsights/workspaces/tables:name]
    ForAllOfAnyValues:StringEquals {
      'DefenderSecureScore_CL',
      'DefenderExposureScore_CL',
      'DefenderConfigurationScore_CL',
      'DefenderAlertAggregates_CL',
      'DefenderRecommendations_CL'
    }
  )
)'''

resource managementWorkspaceRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(managementGroupObjectId)) {
  scope: workspace
  name: guid(workspace.id, managementGroupObjectId, logAnalyticsDataReaderRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', logAnalyticsDataReaderRoleId)
    principalId: managementGroupObjectId
    principalType: 'Group'
    condition: managementTableCondition
    conditionVersion: '2.0'
    description: 'Management: Data Reader beperkt tot score/KPI-tabellen via ABAC'
  }
}

resource managementWorkbookRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(managementGroupObjectId)) {
  name: guid(resourceGroup().id, managementGroupObjectId, workbookReaderRoleId, 'workbook')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', workbookReaderRoleId)
    principalId: managementGroupObjectId
    principalType: 'Group'
    description: 'Management: Workbook Reader op resource group'
  }
}

// ============================================================
// WERKPLEK — Apparaat/endpoint-tabellen
// ============================================================
var werkplekTableCondition = '''(
  (
    !(ActionMatches{'Microsoft.OperationalInsights/workspaces/tables/data/read'})
  )
  OR
  (
    @Resource[Microsoft.OperationalInsights/workspaces/tables:name]
    ForAllOfAnyValues:StringEquals {
      'DefenderDeviceInventory_CL',
      'DefenderSoftwareInventory_CL',
      'DefenderAVHealth_CL',
      'DefenderSecureConfig_CL',
      'DefenderVulnDelta_CL',
      'IntuneDevices_CL',
      'IntuneDetectedApps_CL',
      'IntuneComplianceReports_CL'
    }
  )
)'''

resource werkplekWorkspaceRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(werkplekGroupObjectId)) {
  scope: workspace
  name: guid(workspace.id, werkplekGroupObjectId, logAnalyticsDataReaderRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', logAnalyticsDataReaderRoleId)
    principalId: werkplekGroupObjectId
    principalType: 'Group'
    condition: werkplekTableCondition
    conditionVersion: '2.0'
    description: 'Werkplek: Data Reader beperkt tot device/endpoint-tabellen via ABAC'
  }
}

resource werkplekWorkbookRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(werkplekGroupObjectId)) {
  name: guid(resourceGroup().id, werkplekGroupObjectId, workbookReaderRoleId, 'workbook')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', workbookReaderRoleId)
    principalId: werkplekGroupObjectId
    principalType: 'Group'
    description: 'Werkplek: Workbook Reader op resource group'
  }
}

// ============================================================
// SECURITY — Alle tabellen (geen ABAC-restrictie)
// ============================================================
resource securityWorkspaceRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(securityGroupObjectId)) {
  scope: workspace
  name: guid(workspace.id, securityGroupObjectId, logAnalyticsDataReaderRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', logAnalyticsDataReaderRoleId)
    principalId: securityGroupObjectId
    principalType: 'Group'
    description: 'Security: Data Reader met volledige tabeltoegang (geen ABAC-conditie)'
  }
}

resource securityWorkbookRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(securityGroupObjectId)) {
  name: guid(resourceGroup().id, securityGroupObjectId, workbookContributorRoleId, 'workbook')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', workbookContributorRoleId)
    principalId: securityGroupObjectId
    principalType: 'Group'
    description: 'Security: Workbook Contributor op resource group'
  }
}

// ============================================================
// Function App MI — Monitoring Metrics Publisher op DCRs
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
