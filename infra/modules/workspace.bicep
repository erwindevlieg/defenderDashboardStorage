// ============================================================
// workspace.bicep — Log Analytics Workspace + Custom Tables
// ============================================================
//
// Table plan & retention decision matrix
// --------------------------------------
// Analytics plan is used for tables that are queried interactively from
// dashboards or joined across tables. It is more expensive per GB but
// supports the full KQL surface and shorter query latency.
//
// Basic plan is used for high-volume tables that are queried infrequently
// (forensics / inventory snapshots / aggregations done elsewhere). Lower
// ingest cost, restricted query surface, and a fixed 30-day interactive
// window before data ages into archive.
//
// Retention tiers (interactive / total):
//   * Scores (Exposure, Secure, Configuration)     — 730 / 2556 (2y / 7y)
//     Trend data; small volume; long history is the whole point.
//   * Long archive analytics                       — 365 / 1826 (1y / 5y)
//     SecureScoreControls, AlertAggregates, Recommendations — moderate
//     volume, used in compliance / audit reviews.
//   * Standard analytics inventory                 — 365 /  730 (1y / 2y)
//     DeviceInventory, AVHealth, VulnDelta, IntuneDevices, ASREvents,
//     ProtectionState, AVOutdated, AVDetections — high enough volume to
//     justify the shorter archive window.
//   * Basic tables                                 —  30 /  730 (basic)
//     SoftwareInventory, SecureConfig, DeviceSoftware, IntuneCompliance.
//   * Basic short                                  —  30 /  365 (basic)
//     IntuneDetectedApps — volatile, low historical value.
//
// All retention windows are exposed as parameters so a deployer can dial
// them down once cost-baseline KQL on each `_CL` table is in hand.

@description('Location for all resources')
param location string = resourceGroup().location

@description('Name of the workspace')
param workspaceName string

@description('Tags applied to all resources')
param tags object = {}

@description('Daily ingestion quota in GB (protection against runaway cost)')
param dailyQuotaGb int = 10

@description('Retention in days for the workspace (default 90, CIS 5.3.1 minimum)')
@minValue(30)
@maxValue(730)
param retentionInDays int = 90

@description('Interactive retention for score tables (Exposure / Secure / Configuration). Default 730 (2 years).')
@minValue(30)
@maxValue(730)
param scoreInteractiveRetentionDays int = 730

@description('Total retention (interactive + archive) for score tables. Default 2556 (7 years).')
@minValue(30)
@maxValue(4383)
param scoreArchiveRetentionDays int = 2556

@description('Interactive retention for Analytics inventory and archive tables. Default 365 (1 year).')
@minValue(30)
@maxValue(730)
param analyticsInteractiveRetentionDays int = 365

@description('Total retention for long-archive Analytics tables (SecureScoreControls, AlertAggregates, Recommendations). Default 1826 (5 years).')
@minValue(30)
@maxValue(4383)
param analyticsArchiveRetentionDays int = 1826

@description('Total retention for standard Analytics inventory tables. Default 730 (2 years).')
@minValue(30)
@maxValue(4383)
param inventoryArchiveRetentionDays int = 730

@description('Total retention for Basic tables. Default 730 (2 years).')
@minValue(30)
@maxValue(4383)
param basicRetentionDays int = 730

@description('Total retention for short-lived Basic tables (Intune detected apps). Default 365 (1 year).')
@minValue(30)
@maxValue(4383)
param basicAppsRetentionDays int = 365

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
      disableLocalAuth: true // Entra ID auth only
      enableLogAccessUsingOnlyResourcePermissions: false // Workspace-only mode (ABAC)
      enableDataExport: false // Prevent accidental data export
      immediatePurgeDataOn30Days: false
    }

    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Delete lock
resource workspaceLock 'Microsoft.Authorization/locks@2020-05-01' = {
  name: 'lock-${workspace.name}'
  scope: workspace
  properties: {
    level: 'CanNotDelete'
    notes: 'Log Analytics workspace must not be deleted without explicit approval.'
  }
}

// ============================================================
// Custom tables — Analytics plan (dashboard queries)
// ============================================================
resource tableExposureScore 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderExposureScore_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: scoreInteractiveRetentionDays
    totalRetentionInDays: scoreArchiveRetentionDays
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
    retentionInDays: scoreInteractiveRetentionDays
    totalRetentionInDays: scoreArchiveRetentionDays
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

// SecureScoreControls: Analytics — which controls contribute to the Secure Score
resource tableSecureScoreControls 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderSecureScoreControls_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: analyticsInteractiveRetentionDays
    totalRetentionInDays: analyticsArchiveRetentionDays
    schema: {
      name: 'DefenderSecureScoreControls_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'ControlId', type: 'string' }
        { name: 'Title', type: 'string' }
        { name: 'ControlCategory', type: 'string' }
        { name: 'ActionType', type: 'string' }
        { name: 'MaxScore', type: 'real' }
        { name: 'CurrentScore', type: 'real' }
        { name: 'ImplementationStatus', type: 'string' }
        { name: 'LastModifiedDateTime', type: 'datetime' }
      ]
    }
  }
}

resource tableConfigScore 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderConfigurationScore_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: scoreInteractiveRetentionDays
    totalRetentionInDays: scoreArchiveRetentionDays
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
    retentionInDays: analyticsInteractiveRetentionDays
    totalRetentionInDays: analyticsArchiveRetentionDays
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
    retentionInDays: analyticsInteractiveRetentionDays
    totalRetentionInDays: analyticsArchiveRetentionDays
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
        { name: 'RelatedSoftwareId', type: 'string' } // Join with SoftwareInventory
      ]
    }
  }
}

// ============================================================
// Custom tables — Analytics plan (dashboard queries + joins)
// ============================================================

// DeviceInventory: Analytics — joined with AVHealth, VulnDelta, IntuneDevices
resource tableDeviceInventory 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderDeviceInventory_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: analyticsInteractiveRetentionDays
    totalRetentionInDays: inventoryArchiveRetentionDays
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

// AVHealth: Analytics — join with DeviceInventory for per-device AV status
resource tableAVHealth 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderAVHealth_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: analyticsInteractiveRetentionDays
    totalRetentionInDays: inventoryArchiveRetentionDays
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

// VulnDelta: Analytics — join with DeviceInventory for per-device vulnerabilities
resource tableVulnDelta 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderVulnDelta_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: analyticsInteractiveRetentionDays
    totalRetentionInDays: inventoryArchiveRetentionDays
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

// IntuneDevices: Analytics — join with DeviceInventory via AadDeviceId
resource tableIntuneDevices 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'IntuneDevices_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: analyticsInteractiveRetentionDays
    totalRetentionInDays: inventoryArchiveRetentionDays
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

// ASR Events: Analytics — daily aggregate of ASR blocks/audits
resource tableASREvents 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderASREvents_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: analyticsInteractiveRetentionDays
    totalRetentionInDays: inventoryArchiveRetentionDays
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

// ProtectionState: Analytics — tamper / cloud / realtime protection status per config
resource tableProtectionState 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderProtectionState_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: analyticsInteractiveRetentionDays
    totalRetentionInDays: inventoryArchiveRetentionDays
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

// AVOutdated: Analytics — devices with outdated AV (via Advanced Hunting)
resource tableAVOutdated 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderAVOutdated_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: analyticsInteractiveRetentionDays
    totalRetentionInDays: inventoryArchiveRetentionDays
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

// AVDetections: Analytics — daily aggregate of malware detections (via Advanced Hunting)
resource tableAVDetections 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderAVDetections_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: analyticsInteractiveRetentionDays
    totalRetentionInDays: inventoryArchiveRetentionDays
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
// Custom tables — Basic plan (standalone queries, cheaper ingest)
// ============================================================
resource tableSoftwareInventory 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderSoftwareInventory_CL'
  properties: {
    plan: 'Basic'
    totalRetentionInDays: basicRetentionDays
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
    totalRetentionInDays: basicRetentionDays
    schema: {
      name: 'DefenderSecureConfig_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'DeviceId', type: 'string' }        // MDE device ID
        { name: 'AadDeviceId', type: 'string' }     // Entra device ID — join with Intune
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
// Link table — Device ↔ Software relationship
// ============================================================
resource tableDeviceSoftware 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderDeviceSoftware_CL'
  properties: {
    plan: 'Basic'
    totalRetentionInDays: basicRetentionDays
    schema: {
      name: 'DefenderDeviceSoftware_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'DeviceId', type: 'string' }        // MDE device ID — join with DeviceInventory
        { name: 'AadDeviceId', type: 'string' }     // Entra device ID — join with Intune
        { name: 'DeviceName', type: 'string' }
        { name: 'SoftwareId', type: 'string' }      // Join with SoftwareInventory
        { name: 'SoftwareName', type: 'string' }
        { name: 'SoftwareVendor', type: 'string' }
        { name: 'SoftwareVersion', type: 'string' }
      ]
    }
  }
}

// ============================================================
// Intune tables — Basic plan (standalone)
// ============================================================
resource tableIntuneApps 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'IntuneDetectedApps_CL'
  properties: {
    plan: 'Basic'
    totalRetentionInDays: basicAppsRetentionDays
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
    totalRetentionInDays: basicRetentionDays
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
@description('Resource ID of the workspace')
output workspaceId string = workspace.id

@description('Name of the workspace')
output workspaceName string = workspace.name

@description('Workspace customer ID (used in queries)')
output workspaceCustomerId string = workspace.properties.customerId
