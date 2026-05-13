// ============================================================
// AUTO-GENERATED — do not edit manually
// Run: python scripts/generate.py
// ============================================================

@description('Resource ID van de Log Analytics workspace')
param workspaceId string

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: last(split(workspaceId, '/'))
}

// Defender Alert Aggregates — from defender-alert-aggregates.yaml
resource table_alertAggregates 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderAlertAggregates_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 365
    totalRetentionInDays: 1826
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

// Defender Antivirus Health — from defender-av-health.yaml
resource table_avHealth 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderAVHealth_CL'
  properties: {
    plan: 'Basic'
    totalRetentionInDays: 365
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

// Defender Configuration Score — from defender-configuration-score.yaml
resource table_configurationScore 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
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

// Defender Device Inventory — from defender-device-inventory.yaml
resource table_deviceInventory 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderDeviceInventory_CL'
  properties: {
    plan: 'Basic'
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
        { name: 'RiskScore', type: 'string' }
        { name: 'ExposureLevel', type: 'string' }
        { name: 'HealthStatus', type: 'string' }
        { name: 'OnboardingStatus', type: 'string' }
        { name: 'LastSeen', type: 'datetime' }
      ]
    }
  }
}

// Defender Device Software Mapping — from defender-device-software.yaml
resource table_deviceSoftware 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderDeviceSoftware_CL'
  properties: {
    plan: 'Basic'
    totalRetentionInDays: 730
    schema: {
      name: 'DefenderDeviceSoftware_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'DeviceId', type: 'string' }
        { name: 'AadDeviceId', type: 'string' }
        { name: 'DeviceName', type: 'string' }
        { name: 'SoftwareId', type: 'string' }
        { name: 'SoftwareName', type: 'string' }
        { name: 'SoftwareVendor', type: 'string' }
        { name: 'SoftwareVersion', type: 'string' }
      ]
    }
  }
}

// Defender Exposure Score — from defender-exposure-score.yaml
resource table_exposureScore 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderExposureScore_CL'
  properties: {
    plan: 'Analytics'
    retentionInDays: 730
    totalRetentionInDays: 2556
    schema: {
      name: 'DefenderExposureScore_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'ExposureScore', type: 'real' }
      ]
    }
  }
}

// Defender Security Recommendations — from defender-recommendations.yaml
resource table_recommendations 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
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
        { name: 'RelatedSoftwareId', type: 'string' }
      ]
    }
  }
}

// Defender Secure Configuration Assessment — from defender-secure-config.yaml
resource table_secureConfig 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderSecureConfig_CL'
  properties: {
    plan: 'Basic'
    totalRetentionInDays: 730
    schema: {
      name: 'DefenderSecureConfig_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'DeviceId', type: 'string' }
        { name: 'AadDeviceId', type: 'string' }
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

// Microsoft Secure Score — from defender-secure-score.yaml
resource table_secureScore 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
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

// Defender Software Inventory — from defender-software-inventory.yaml
resource table_softwareInventory 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
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

// Defender Vulnerability Delta — from defender-vuln-delta.yaml
resource table_vulnDelta 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'DefenderVulnDelta_CL'
  properties: {
    plan: 'Basic'
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

// Intune Compliance Reports — from intune-compliance.yaml
resource table_intuneCompliance 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
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

// Intune Detected Applications — from intune-detected-apps.yaml
resource table_intuneDetectedApps 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
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

// Intune Managed Devices — from intune-devices.yaml
resource table_intuneDevices 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'IntuneDevices_CL'
  properties: {
    plan: 'Basic'
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
      ]
    }
  }
}
