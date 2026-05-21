// ============================================================
// rbac-approles.bicep — App Role Assignments via Deployment Script
// Wijst Defender/Graph app roles toe aan de Managed Identity
// ============================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Tags applied to all resources')
param tags object = {}

@description('Principal ID (Object ID) of the Managed Identity')
param identityPrincipalId string

@description('Resource ID van een UAMI die de deployment script uitvoert (moet AppRoleAssignment.ReadWrite.All hebben)')
param scriptRunnerIdentityId string

@description('Timestamp for force-rerun (use utcNow())')
param utcValue string = utcNow()

resource assignAppRoles 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'script-assign-app-roles'
  location: location
  tags: tags
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${scriptRunnerIdentityId}': {}
    }
  }
  properties: {
    azPowerShellVersion: '11.0'
    retentionInterval: 'PT1H'
    forceUpdateTag: utcValue
    scriptContent: loadTextContent('../scripts/assign-app-roles.ps1')
    arguments: '-ManagedIdentityPrincipalId "${identityPrincipalId}"'
    timeout: 'PT10M'
  }
}
