// ============================================================
// workspace.bicep — Log Analytics Workspace + Custom Tabellen
// ============================================================

@description('Locatie voor alle resources')
param location string = resourceGroup().location

@description('Naam van de workspace')
param workspaceName string

@description('Tags voor alle resources')
param tags object = {}

@description('Dagelijks ingestie quotum in GB (bescherming tegen kosten-explosie)')
param dailyQuotaGb int = 10

@description('Retentie in dagen voor de workspace (standaard 90, CIS 5.3.1 minimum)')
@minValue(30)
@maxValue(730)
param retentionInDays int = 90

// ============================================================
// Workspace
// ============================================================
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: retentionInDays

    workspaceCapping: {
      dailyQuotaGb: dailyQuotaGb
    }

    features: {
      disableLocalAuth: true // Alleen Entra ID auth
      enableLogAccessUsingOnlyResourcePermissions: false // Workspace-only modus (ABAC)
      enableDataExport: false // Voorkom onbedoelde data-export
      immediatePurgeDataOn30Days: false
    }

    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Verwijder-vergrendeling
resource workspaceLock 'Microsoft.Authorization/locks@2020-05-01' = {
  name: 'lock-${workspace.name}'
  scope: workspace
  properties: {
    level: 'CanNotDelete'
    notes: 'Log Analytics workspace mag niet verwijderd worden zonder expliciete goedkeuring.'
  }
}

// ============================================================
// Custom Tabellen — Analytics Plan (dashboard queries)
// ============================================================
resource tableExposureScore 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderExposureScore_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 730 // 2 jaar interactief
    totalRetentionInDays: 2556 // 7 jaar totaal
    schema: {
      name: 'DefenderExposureScore_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'ExposureScore', type: 'real' }
      ]
    }
  }
}

resource tableSecureScore 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderSecureScore_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 730
    totalRetentionInDays: 2556
    schema: {
      name: 'DefenderSecureScore_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'CurrentScore', type: 'real' }
        { name: 'MaxScore', type: 'real' }
        { name: 'AverageComparativeScore', type: 'real' }
      ]
    }
  }
}

resource tableConfigScore 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderConfigurationScore_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 730
    totalRetentionInDays: 2556
    schema: {
      name: 'DefenderConfigurationScore_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'ConfigurationScore', type: 'real' }
      ]
    }
  }
}

resource tableAlertAggregates 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderAlertAggregates_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 365
    totalRetentionInDays: 1826 // 5 jaar
    schema: {
      name: 'DefenderAlertAggregates_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'TotalAlerts', type: 'int' }
        { name: 'HighSeverity', type: 'int' }
        { name: 'MediumSeverity', type: 'int' }
        { name: 'LowSeverity', type: 'int' }
        { name: 'MTTR_Hours', type: 'real' }
        { name: 'MTTD_Hours', type: 'real' }
      ]
    }
  }
}

resource tableRecommendations 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderRecommendations_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 365
    totalRetentionInDays: 1826
    schema: {
      name: 'DefenderRecommendations_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'RecommendationId', type: 'string' }
        { name: 'RecommendationName', type: 'string' }
        { name: 'RecommendationCategory', type: 'string' }
        { name: 'Severity', type: 'string' }
        { name: 'Status', type: 'string' }
        { name: 'ExposedMachines', type: 'int' }
        { name: 'RemediationType', type: 'string' }
        { name: 'Vendor', type: 'string' }
        { name: 'ProductName', type: 'string' }
        { name: 'SubCategory', type: 'string' }
        { name: 'RelatedSoftwareId', type: 'string' } // Join met SoftwareInventory
      ]
    }
  }
}

// ============================================================
// Custom Tabellen — Analytics Plan (dashboard queries + joins)
// ============================================================

// DeviceInventory: Analytics — wordt gejoind met AVHealth, VulnDelta, IntuneDevices
resource tableDeviceInventory 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderDeviceInventory_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 365
    totalRetentionInDays: 730
    schema: {
      name: 'DefenderDeviceInventory_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'DeviceId', type: 'string' }
        { name: 'AadDeviceId', type: 'string' }
        { name: 'DeviceName', type: 'string' }
        { name: 'OsPlatform', type: 'string' }
        { name: 'OsVersion', type: 'string' }
        { name: 'OsBuild', type: 'string' }
        { name: 'RiskScore', type: 'string' }
        { name: 'ExposureLevel', type: 'string' }
        { name: 'HealthStatus', type: 'string' }
        { name: 'OnboardingStatus', type: 'string' }
        { name: 'LastSeen', type: 'datetime' }
        { name: 'FirstSeen', type: 'datetime' }
        { name: 'LastLoggedOnUser', type: 'string' }
        { name: 'LastIpAddress', type: 'string' }
        { name: 'LastExternalIpAddress', type: 'string' }
        { name: 'AgentVersion', type: 'string' }
        { name: 'RbacGroupName', type: 'string' }
      ]
    }
  }
}

// AVHealth: Analytics — join met DeviceInventory voor AV status per device
resource tableAVHealth 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderAVHealth_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 365
    totalRetentionInDays: 730
    schema: {
      name: 'DefenderAVHealth_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'DeviceId', type: 'string' }
        { name: 'AadDeviceId', type: 'string' }
        { name: 'DeviceName', type: 'string' }
        { name: 'AVEngineVersion', type: 'string' }
        { name: 'AVSignatureVersion', type: 'string' }
        { name: 'AVPlatformVersion', type: 'string' }
        { name: 'AVMode', type: 'string' }
        { name: 'AVSignatureUpdateTime', type: 'datetime' }
        { name: 'QuickScanResult', type: 'string' }
        { name: 'QuickScanTime', type: 'datetime' }
      ]
    }
  }
}

// VulnDelta: Analytics — join met DeviceInventory voor vulns per device
resource tableVulnDelta 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderVulnDelta_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 365
    totalRetentionInDays: 730
    schema: {
      name: 'DefenderVulnDelta_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'DeviceId', type: 'string' }
        { name: 'AadDeviceId', type: 'string' }
        { name: 'CveId', type: 'string' }
        { name: 'EventType', type: 'string' }
        { name: 'SoftwareId', type: 'string' }
        { name: 'SoftwareName', type: 'string' }
        { name: 'SoftwareVendor', type: 'string' }
        { name: 'SoftwareVersion', type: 'string' }
        { name: 'VulnerabilitySeverityLevel', type: 'string' }
      ]
    }
  }
}

// IntuneDevices: Analytics — join met DeviceInventory via AadDeviceId
resource tableIntuneDevices 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'IntuneDevices_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 365
    totalRetentionInDays: 730
    schema: {
      name: 'IntuneDevices_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'DeviceId', type: 'string' }
        { name: 'AadDeviceId', type: 'string' }
        { name: 'DeviceName', type: 'string' }
        { name: 'OperatingSystem', type: 'string' }
        { name: 'OsVersion', type: 'string' }
        { name: 'ComplianceState', type: 'string' }
        { name: 'EnrollmentType', type: 'string' }
        { name: 'LastSyncDateTime', type: 'datetime' }
        { name: 'ManagementAgent', type: 'string' }
        { name: 'UserPrincipalName', type: 'string' }
        { name: 'UserDisplayName', type: 'string' }
        { name: 'IsEncrypted', type: 'boolean' }
        { name: 'Model', type: 'string' }
        { name: 'Manufacturer', type: 'string' }
        { name: 'EnrolledDateTime', type: 'datetime' }
      ]
    }
  }
}

// ASR Events: Analytics — dagelijks aggregaat van ASR blocks/audits
resource tableASREvents 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderASREvents_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 365
    totalRetentionInDays: 730
    schema: {
      name: 'DefenderASREvents_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'RuleName', type: 'string' }
        { name: 'ActionType', type: 'string' }
        { name: 'EventCount', type: 'int' }
        { name: 'UniqueDevices', type: 'int' }
      ]
    }
  }
}

// ProtectionState: Analytics — tamper/cloud/realtime protection status per config
resource tableProtectionState 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderProtectionState_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 365
    totalRetentionInDays: 730
    schema: {
      name: 'DefenderProtectionState_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'ConfigurationId', type: 'string' }
        { name: 'ConfigurationName', type: 'string' }
        { name: 'ConfigurationCategory', type: 'string' }
        { name: 'ConfigurationSubcategory', type: 'string' }
        { name: 'CompliantDevices', type: 'int' }
        { name: 'NonCompliantDevices', type: 'int' }
        { name: 'TotalDevices', type: 'int' }
      ]
    }
  }
}

// AVOutdated: Analytics — devices met verouderde AV (via Advanced Hunting)
resource tableAVOutdated 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderAVOutdated_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 365
    totalRetentionInDays: 730
    schema: {
      name: 'DefenderAVOutdated_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'DeviceId', type: 'string' }
        { name: 'DeviceName', type: 'string' }
        { name: 'OSPlatform', type: 'string' }
        { name: 'AvMode', type: 'string' }
        { name: 'AvIsSignatureUpToDate', type: 'string' }
        { name: 'AvIsEngineUpToDate', type: 'string' }
        { name: 'AvIsPlatformUpToDate', type: 'string' }
        { name: 'AvSignatureVersion', type: 'string' }
        { name: 'AvEngineVersion', type: 'string' }
        { name: 'AvPlatformVersion', type: 'string' }
        { name: 'AvSignaturePublishTime', type: 'datetime' }
        { name: 'AvSignatureDataRefreshTime', type: 'datetime' }
        { name: 'SignatureAgeDays', type: 'int' }
      ]
    }
  }
}

// AVDetections: Analytics — dagelijks aggregaat van malware-detecties (via Advanced Hunting)
resource tableAVDetections 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderAVDetections_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 365
    totalRetentionInDays: 730
    schema: {
      name: 'DefenderAVDetections_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'ThreatName', type: 'string' }
        { name: 'DetectionSource', type: 'string' }
        { name: 'DetectionCount', type: 'int' }
        { name: 'UniqueDevices', type: 'int' }
        { name: 'RemediatedCount', type: 'int' }
      ]
    }
  }
}

// ============================================================
// Custom Tabellen — Basic Plan (standalone queries, goedkoper)
// ============================================================
resource tableSoftwareInventory 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderSoftwareInventory_CL'
  properties: {
    plan: 'Basic'
    totalRetentionInDays: 730
    schema: {
      name: 'DefenderSoftwareInventory_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'SoftwareId', type: 'string' }
        { name: 'SoftwareName', type: 'string' }
        { name: 'SoftwareVendor', type: 'string' }
        { name: 'SoftwareVersion', type: 'string' }
        { name: 'NumberOfWeaknesses', type: 'int' }
        { name: 'NumberOfDevices', type: 'int' }
        { name: 'EndOfSupportStatus', type: 'string' }
      ]
    }
  }
}

resource tableSecureConfig 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderSecureConfig_CL'
  properties: {
    plan: 'Basic'
    totalRetentionInDays: 730
    schema: {
      name: 'DefenderSecureConfig_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'DeviceId', type: 'string' }        // MDE device ID
        { name: 'AadDeviceId', type: 'string' }     // Entra device ID — join met Intune
        { name: 'DeviceName', type: 'string' }
        { name: 'ConfigurationId', type: 'string' }
        { name: 'ConfigurationCategory', type: 'string' }
        { name: 'ConfigurationSubcategory', type: 'string' }
        { name: 'IsCompliant', type: 'boolean' }
        { name: 'IsApplicable', type: 'boolean' }
      ]
    }
  }
}

// ============================================================
// Koppeltabel — Device ↔ Software relatie
// ============================================================
resource tableDeviceSoftware 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderDeviceSoftware_CL'
  properties: {
    plan: 'Basic'
    totalRetentionInDays: 730
    schema: {
      name: 'DefenderDeviceSoftware_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'DeviceId', type: 'string' }        // MDE device ID — join met DeviceInventory
        { name: 'AadDeviceId', type: 'string' }     // Entra device ID — join met Intune
        { name: 'DeviceName', type: 'string' }
        { name: 'SoftwareId', type: 'string' }      // Join met SoftwareInventory
        { name: 'SoftwareName', type: 'string' }
        { name: 'SoftwareVendor', type: 'string' }
        { name: 'SoftwareVersion', type: 'string' }
      ]
    }
  }
}

// ============================================================
// Intune Tabellen — Basic Plan (standalone)
// ============================================================
resource tableIntuneApps 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'IntuneDetectedApps_CL'
  properties: {
    plan: 'Basic'
    totalRetentionInDays: 365
    schema: {
      name: 'IntuneDetectedApps_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'ApplicationName', type: 'string' }
        { name: 'ApplicationVersion', type: 'string' }
        { name: 'DeviceCount', type: 'int' }
        { name: 'Platform', type: 'string' }
      ]
    }
  }
}

resource tableIntuneCompliance 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'IntuneComplianceReports_CL'
  properties: {
    plan: 'Basic'
    totalRetentionInDays: 730
    schema: {
      name: 'IntuneComplianceReports_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'PolicyName', type: 'string' }
        { name: 'PolicyId', type: 'string' }
        { name: 'CompliantDevices', type: 'int' }
        { name: 'NonCompliantDevices', type: 'int' }
        { name: 'ErrorDevices', type: 'int' }
        { name: 'NotApplicableDevices', type: 'int' }
        { name: 'Platform', type: 'string' }
      ]
    }
  }
}

// ============================================================
// Outputs
// ============================================================
@description('Resource ID van de workspace')
output workspaceId string = workspace.id

@description('Naam van de workspace')
output workspaceName string = workspace.name

@description('Workspace customer ID (voor queries)')
output workspaceCustomerId string = workspace.properties.customerId
