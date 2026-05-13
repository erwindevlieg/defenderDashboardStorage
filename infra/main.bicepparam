using 'main.bicep'

param resourceToken = 'prod01'
param location = 'westeurope'

// Entra Security Group Object IDs — vul in na aanmaken van de groepen
// Gebruik: az ad group show --group "sg-defender-dashboard-management" --query id -o tsv
param managementGroupObjectId = ''
param werkplekGroupObjectId = ''
param securityGroupObjectId = ''

// Bootstrap UAMI voor app role assignments — vul in als beschikbaar
param scriptRunnerIdentityId = ''
