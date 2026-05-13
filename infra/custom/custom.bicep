// ============================================================
// custom.bicep — Orchestrator voor custom connectors
//
// Voeg hier je eigen connector-modules toe.
// Elke module wordt apart gedeployed en krijgt de workspace
// en DCE als parameters mee.
//
// VOORBEELD (uncomment en pas aan):
//
// module entraRiskyUsers '_example.bicep' = {
//   name: 'deploy-custom-entra-risky-users'
//   params: {
//     workspaceId: workspaceId
//     dceId: dceId
//     location: location
//     resourceToken: resourceToken
//     tags: tags
//   }
// }
//
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

// Voeg hieronder je custom connector modules toe:
// (zie _example.bicep als startpunt)

// Parameters worden gebruikt zodra je een module toevoegt.
// Suppress unused-param warnings voor lege orchestrator.
#disable-next-line no-unused-params no-unused-vars
var _dependencies = [workspaceId, dceId, location, resourceToken, string(tags)]
