// ============================================================
// _example.bicep — Voorbeeld: Entra Risky Users connector
//
// GEBRUIK:
//   1. Kopieer dit bestand en hernoem naar je databron
//   2. Pas de tabel, kolommen, stream en data flow aan
//   3. Voeg een endpoint toe aan function-app/config/endpoints.json
//   4. Importeer je module in infra/custom/custom.bicep
//   5. Recompile: az bicep build --file infra/main.bicep --outfile azuredeploy.json
// ============================================================

@description('Resource ID van de Log Analytics workspace')
param workspaceId string

@description('Resource ID van de Data Collection Endpoint')
param dceId string

@description('Locatie voor alle resources')
param location string = resourceGroup().location

@description('Unieke token voor resource namen')
param resourceToken string

@description('Tags voor alle resources')
param tags object = {}

// ============================================================
// Stap 1: Tabel in Log Analytics
// ============================================================
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: last(split(workspaceId, '/'))
}

resource table 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'EntraRiskyUsers_CL'           // <-- Pas aan: tabelnaam (moet eindigen op _CL)
  properties: {
    plan: 'Analytics'                   // <-- 'Analytics' of 'Basic'
    retentionInDays: 365                // <-- Alleen voor Analytics plan
    totalRetentionInDays: 1826
    schema: {
      name: 'EntraRiskyUsers_CL'       // <-- Zelfde als name hierboven
      columns: [
        // TimeGenerated is verplicht
        { name: 'TimeGenerated', type: 'datetime' }
        // Voeg hier je eigen kolommen toe:
        { name: 'UserId', type: 'string' }
        { name: 'UserDisplayName', type: 'string' }
        { name: 'UserPrincipalName', type: 'string' }
        { name: 'RiskLevel', type: 'string' }
        { name: 'RiskState', type: 'string' }
        { name: 'RiskDetail', type: 'string' }
        { name: 'RiskLastUpdatedDateTime', type: 'datetime' }
      ]
    }
  }
}

// ============================================================
// Stap 2: DCR met stream + data flow
// ============================================================
resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-custom-entra-risky-users-${resourceToken}'  // <-- Pas aan
  location: location
  tags: tags
  properties: {
    dataCollectionEndpointId: dceId
    streamDeclarations: {
      // Stream naam = 'Custom-' + tabelnaam
      'Custom-EntraRiskyUsers_CL': {   // <-- Pas aan
        columns: [
          // Exact dezelfde kolommen als de tabel hierboven
          { name: 'TimeGenerated', type: 'datetime' }
          { name: 'UserId', type: 'string' }
          { name: 'UserDisplayName', type: 'string' }
          { name: 'UserPrincipalName', type: 'string' }
          { name: 'RiskLevel', type: 'string' }
          { name: 'RiskState', type: 'string' }
          { name: 'RiskDetail', type: 'string' }
          { name: 'RiskLastUpdatedDateTime', type: 'datetime' }
        ]
      }
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: workspaceId
          name: 'defender-dashboard-workspace'
        }
      ]
    }
    dataFlows: [
      {
        streams: [ 'Custom-EntraRiskyUsers_CL' ]  // <-- Pas aan
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-EntraRiskyUsers_CL'  // <-- Pas aan
      }
    ]
  }
}

// ============================================================
// Outputs (optioneel, voor gebruik in custom.bicep)
// ============================================================
output dcrImmutableId string = dcr.properties.immutableId
output dcrId string = dcr.id
