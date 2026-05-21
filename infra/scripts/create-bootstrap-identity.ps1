<#
.SYNOPSIS
    Creates the one-off bootstrap User-Assigned Managed Identity (UAMI) used
    by the Deploy-to-Azure button to auto-grant Microsoft Graph + Defender
    app roles to the dashboard MI.

.DESCRIPTION
    The deployment template can run a deploymentScript that assigns the
    required Graph / Defender app roles to the dashboard MI on your behalf,
    but only if you provide a ``scriptRunnerIdentityId`` — a UAMI that
    itself holds ``AppRoleAssignment.ReadWrite.All`` on Microsoft Graph.

    Run this script once, as Global Administrator (or Privileged Role
    Administrator), to create that bootstrap identity. The script prints
    the UAMI's Resource ID; paste it into the ``scriptRunnerIdentityId``
    field of every future Deploy-to-Azure deployment.

.PARAMETER ResourceGroup
    Resource group that will hold the bootstrap UAMI. Created if missing.

.PARAMETER IdentityName
    Name of the UAMI to create.

.PARAMETER Location
    Azure region for the UAMI.

.EXAMPLE
    ./create-bootstrap-identity.ps1 -ResourceGroup rg-ddash-bootstrap `
                                    -IdentityName  id-ddash-bootstrap `
                                    -Location      westeurope

.NOTES
    Requirements:
        - PowerShell 7+
        - Azure CLI (``az login`` as Owner on the target subscription)
        - Microsoft.Graph PowerShell module (auto-installed if missing)
        - The signed-in Entra account must be Global Administrator or
          Privileged Role Administrator (to grant a Graph app role).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]  [string] $ResourceGroup,
    [Parameter(Mandatory)]  [string] $IdentityName,
    [Parameter(Mandatory)]  [string] $Location
)

$ErrorActionPreference = 'Stop'

# 1. Ensure Microsoft.Graph module is available
if (-not (Get-Module -ListAvailable Microsoft.Graph.Applications)) {
    Write-Host "Installing Microsoft.Graph.Applications module (current user)..."
    Install-Module Microsoft.Graph.Applications -Scope CurrentUser -Force
}
Import-Module Microsoft.Graph.Applications

# 2. Create RG + UAMI via Azure CLI
Write-Host "Ensuring resource group '$ResourceGroup' in $Location..."
az group create --name $ResourceGroup --location $Location --only-show-errors | Out-Null

Write-Host "Creating UAMI '$IdentityName'..."
$mi = az identity create `
        --resource-group $ResourceGroup `
        --name           $IdentityName `
        --location       $Location `
        --only-show-errors | ConvertFrom-Json

Write-Host "  Resource ID : $($mi.id)"
Write-Host "  Principal ID: $($mi.principalId)"

# 3. Grant AppRoleAssignment.ReadWrite.All on Microsoft Graph
Write-Host "Connecting to Microsoft Graph..."
Connect-MgGraph -Scopes 'AppRoleAssignment.ReadWrite.All','Application.Read.All' -NoWelcome

$graphAppId = '00000003-0000-0000-c000-000000000000'   # Microsoft Graph
$graphSp    = Get-MgServicePrincipal -Filter "appId eq '$graphAppId'"
$appRoleId  = ($graphSp.AppRoles | Where-Object Value -EQ 'AppRoleAssignment.ReadWrite.All').Id

if (-not $appRoleId) {
    throw "Could not find the 'AppRoleAssignment.ReadWrite.All' app role on Microsoft Graph."
}

# Idempotent: skip if already granted
$existing = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $graphSp.Id |
            Where-Object { $_.PrincipalId -eq $mi.principalId -and $_.AppRoleId -eq $appRoleId }

if ($existing) {
    Write-Host "App role 'AppRoleAssignment.ReadWrite.All' already granted — skipping."
} else {
    Write-Host "Granting 'AppRoleAssignment.ReadWrite.All' to $IdentityName on Microsoft Graph..."
    New-MgServicePrincipalAppRoleAssignment `
        -ServicePrincipalId $graphSp.Id `
        -BodyParameter @{
            principalId = $mi.principalId
            resourceId  = $graphSp.Id
            appRoleId   = $appRoleId
        } | Out-Null
    Write-Host "Done."
}

Write-Host ""
Write-Host "============================================================"
Write-Host "Use the following value as 'scriptRunnerIdentityId' in the"
Write-Host "Deploy-to-Azure form:"
Write-Host ""
Write-Host "  $($mi.id)"
Write-Host "============================================================"
