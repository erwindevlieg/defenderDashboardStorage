<#
.SYNOPSIS
    Wijst Defender XDR en Microsoft Graph app roles toe aan een Managed Identity.
.DESCRIPTION
    Dit script wordt uitgevoerd via een Bicep deploymentScript.
    De identity die dit script uitvoert moet AppRoleAssignment.ReadWrite.All hebben.
.PARAMETER ManagedIdentityPrincipalId
    Object ID van de Managed Identity waaraan de app roles worden toegewezen.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ManagedIdentityPrincipalId
)

$ErrorActionPreference = 'Stop'

# Well-known Service Principal App IDs
$defenderAppId = 'fc780465-2017-40d4-a0c5-307022471b92'  # WindowsDefenderATP
$graphAppId = '00000003-0000-0000-c000-000000000000'      # Microsoft Graph

# WindowsDefenderATP App Roles
$defenderRoles = @{
    'Score.Read.All'                  = '02b005dd-4237-4e38-b59f-fdb03dbb7e58'
    'Machine.Read.All'                = 'ea8291d3-4b9a-44b5-bc3a-6cea3026dc79'
    'Vulnerability.Read.All'          = '41269fc5-d04d-4bfd-bce7-43a51cea049a'
    'Alert.Read.All'                  = '71fe6b80-efef-4ac2-a530-00d4755b6c67'
    'AdvancedQuery.Read.All'          = '93489bf5-0fbc-4f2d-b901-33f2fe08ff05'
    'SecurityRecommendation.Read.All' = '6443965c-7440-4abb-830f-f2f7be535ea0'
    'Software.Read.All'               = '37f71c98-d198-41ae-964d-d4e3dddea1e3'
}

# Microsoft Graph App Roles
$graphRoles = @{
    'SecurityEvents.Read.All'                        = 'bf394140-e372-4bf9-a898-299cfc7564e5'
    'ThreatHunting.Read.All'                         = 'dd98c7f5-2d42-42d8-a6d0-7b32b7f11dc0'
    'SecurityAlert.Read.All'                         = '472e4a4d-bb4a-4026-98d1-0b0d74cb74a5'
    'SecurityIncident.Read.All'                      = '45cc0394-e837-488b-a098-1918f48d186c'
    'DeviceManagementManagedDevices.Read.All'         = '2f51be20-0bb4-4fed-bf7b-db946066c75e'
    'DeviceManagementConfiguration.Read.All'          = 'dc377aa6-52d8-4e23-b271-b4ee8372acee'
    'DeviceManagementApps.Read.All'                  = '7a6ee1e7-141e-4cec-ae74-d9db155731ff'
}

function Assign-AppRole {
    param(
        [string]$ServicePrincipalAppId,
        [string]$AppRoleId,
        [string]$AppRoleName,
        [string]$PrincipalId
    )

    # Zoek de service principal op basis van appId
    $sp = Get-MgServicePrincipal -Filter "appId eq '$ServicePrincipalAppId'" -Top 1

    if (-not $sp) {
        Write-Warning "Service Principal met appId '$ServicePrincipalAppId' niet gevonden. Sla over."
        return
    }

    # Controleer of de toewijzing al bestaat
    $existing = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id |
        Where-Object { $_.AppRoleId -eq $AppRoleId -and $_.PrincipalId -eq $PrincipalId }

    if ($existing) {
        Write-Output "[OK] App role '$AppRoleName' is al toegewezen."
        return
    }

    # Wijs de app role toe
    $params = @{
        PrincipalId = $PrincipalId
        ResourceId  = $sp.Id
        AppRoleId   = $AppRoleId
    }

    New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $PrincipalId -BodyParameter $params
    Write-Output "[OK] App role '$AppRoleName' succesvol toegewezen."
}

# Installeer Microsoft.Graph module als nodig
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Applications)) {
    Install-Module Microsoft.Graph.Applications -Force -Scope CurrentUser -AllowClobber
}

Import-Module Microsoft.Graph.Applications

# Connect via Managed Identity
Connect-MgGraph -Identity

Write-Output "=== WindowsDefenderATP App Roles ==="
foreach ($role in $defenderRoles.GetEnumerator()) {
    Assign-AppRole -ServicePrincipalAppId $defenderAppId `
                   -AppRoleId $role.Value `
                   -AppRoleName $role.Key `
                   -PrincipalId $ManagedIdentityPrincipalId
}

Write-Output ""
Write-Output "=== Microsoft Graph App Roles ==="
foreach ($role in $graphRoles.GetEnumerator()) {
    Assign-AppRole -ServicePrincipalAppId $graphAppId `
                   -AppRoleId $role.Value `
                   -AppRoleName $role.Key `
                   -PrincipalId $ManagedIdentityPrincipalId
}

Write-Output ""
Write-Output "Alle app role assignments voltooid."
$DeploymentScriptOutputs = @{ status = 'success' }
