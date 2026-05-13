// ============================================================
// identity.bicep — User-Assigned Managed Identity
// ============================================================

@description('Locatie voor alle resources')
param location string = resourceGroup().location

@description('Unieke token voor resource namen')
param resourceToken string

@description('Tags voor alle resources')
param tags object = {}

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'uai-defender-dashboard-${resourceToken}'
  location: location
  tags: tags
}

@description('Resource ID van de Managed Identity')
output identityId string = userAssignedIdentity.id

@description('Principal ID (Object ID) van de Managed Identity')
output principalId string = userAssignedIdentity.properties.principalId

@description('Client ID van de Managed Identity')
output clientId string = userAssignedIdentity.properties.clientId

@description('Naam van de Managed Identity')
output identityName string = userAssignedIdentity.name
