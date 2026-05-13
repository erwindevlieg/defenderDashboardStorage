// ============================================================
// AUTO-GENERATED — do not edit manually
// Run: python scripts/generate.py
// ============================================================

@description('Locatie voor alle resources')
param location string = resourceGroup().location

@description('Unieke token voor resource namen')
param resourceToken string

@description('Tags voor alle resources')
param tags object = {}

@description('Resource ID van de Log Analytics workspace')
param workspaceId string

@description('Data Collection Endpoint ID')
param dceId string

// Dagelijkse Scores
resource dcr_daily 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-defender-daily-scores-${resourceToken}'
  location: location
  tags: tags
  properties: {
    dataCollectionEndpointId: dceId
    streamDeclarations: {
      'Custom-DefenderAlertAggregates_CL': {
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
      'Custom-DefenderConfigurationScore_CL': {
        columns: [
          { name: 'TimeGenerated', type: 'datetime' }
          { name: 'ConfigurationScore', type: 'real' }
        ]
      }
      'Custom-DefenderExposureScore_CL': {
        columns: [
          { name: 'TimeGenerated', type: 'datetime' }
          { name: 'ExposureScore', type: 'real' }
        ]
      }
      'Custom-DefenderRecommendations_CL': {
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
      'Custom-DefenderSecureScore_CL': {
        columns: [
          { name: 'TimeGenerated', type: 'datetime' }
          { name: 'CurrentScore', type: 'real' }
          { name: 'MaxScore', type: 'real' }
          { name: 'AverageComparativeScore', type: 'real' }
        ]
      }
      'Custom-DefenderVulnDelta_CL': {
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
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: workspaceId
          name: 'defender-dashboard-workspace'
        }
      ]
    }
    dataFlows: [
      {
        streams: [ 'Custom-DefenderAlertAggregates_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderAlertAggregates_CL'
      }
      {
        streams: [ 'Custom-DefenderConfigurationScore_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderConfigurationScore_CL'
      }
      {
        streams: [ 'Custom-DefenderExposureScore_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderExposureScore_CL'
      }
      {
        streams: [ 'Custom-DefenderRecommendations_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderRecommendations_CL'
      }
      {
        streams: [ 'Custom-DefenderSecureScore_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderSecureScore_CL'
      }
      {
        streams: [ 'Custom-DefenderVulnDelta_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderVulnDelta_CL'
      }
    ]
  }
}

// Wekelijkse Snapshots
resource dcr_weekly 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-defender-weekly-snapshots-${resourceToken}'
  location: location
  tags: tags
  properties: {
    dataCollectionEndpointId: dceId
    streamDeclarations: {
      'Custom-DefenderAVHealth_CL': {
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
      'Custom-DefenderDeviceInventory_CL': {
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
      'Custom-DefenderDeviceSoftware_CL': {
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
      'Custom-DefenderSecureConfig_CL': {
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
      'Custom-DefenderSoftwareInventory_CL': {
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
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: workspaceId
          name: 'defender-dashboard-workspace'
        }
      ]
    }
    dataFlows: [
      {
        streams: [ 'Custom-DefenderAVHealth_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderAVHealth_CL'
      }
      {
        streams: [ 'Custom-DefenderDeviceInventory_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderDeviceInventory_CL'
      }
      {
        streams: [ 'Custom-DefenderDeviceSoftware_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderDeviceSoftware_CL'
      }
      {
        streams: [ 'Custom-DefenderSecureConfig_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderSecureConfig_CL'
      }
      {
        streams: [ 'Custom-DefenderSoftwareInventory_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderSoftwareInventory_CL'
      }
    ]
  }
}

// Intune Data
resource dcr_intune 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-defender-intune-${resourceToken}'
  location: location
  tags: tags
  properties: {
    dataCollectionEndpointId: dceId
    streamDeclarations: {
      'Custom-IntuneComplianceReports_CL': {
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
      'Custom-IntuneDetectedApps_CL': {
        columns: [
          { name: 'TimeGenerated', type: 'datetime' }
          { name: 'ApplicationName', type: 'string' }
          { name: 'ApplicationVersion', type: 'string' }
          { name: 'DeviceCount', type: 'int' }
          { name: 'Platform', type: 'string' }
        ]
      }
      'Custom-IntuneDevices_CL': {
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
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: workspaceId
          name: 'defender-dashboard-workspace'
        }
      ]
    }
    dataFlows: [
      {
        streams: [ 'Custom-IntuneComplianceReports_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-IntuneComplianceReports_CL'
      }
      {
        streams: [ 'Custom-IntuneDetectedApps_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-IntuneDetectedApps_CL'
      }
      {
        streams: [ 'Custom-IntuneDevices_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-IntuneDevices_CL'
      }
    ]
  }
}

@description('DCR Daily — Immutable ID')
output dcrDailyImmutableId string = dcr_daily.properties.immutableId

@description('DCR Daily — Resource ID')
output dcrDailyId string = dcr_daily.id

@description('DCR Weekly — Immutable ID')
output dcrWeeklyImmutableId string = dcr_weekly.properties.immutableId

@description('DCR Weekly — Resource ID')
output dcrWeeklyId string = dcr_weekly.id

@description('DCR Intune — Immutable ID')
output dcrIntuneImmutableId string = dcr_intune.properties.immutableId

@description('DCR Intune — Resource ID')
output dcrIntuneId string = dcr_intune.id
