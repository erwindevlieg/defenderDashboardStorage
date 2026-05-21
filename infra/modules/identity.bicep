// ============================================================
// identity.bicep — User-Assigned Managed Identity
// ============================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique token for resource names')
param resourceToken string

@description('Tags applied to all resources')
param tags object = {}

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'uai-defender-dashboard-${resourceToken}'
  location: location
  tags: tags
}

@description('Resource ID of the Managed Identity')
output identityId string = userAssignedIdentity.id

@description('Principal ID (Object ID) of the Managed Identity')
output principalId string = userAssignedIdentity.properties.principalId

@description('Client ID of the Managed Identity')
output clientId string = userAssignedIdentity.properties.clientId

@description('Name of the Managed Identity')
output identityName string = userAssignedIdentity.name
