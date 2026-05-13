// ============================================================
// dcr.bicep — Data Collection Endpoint + Rules
// ============================================================

@description('Locatie voor alle resources')
param location string = resourceGroup().location

@description('Unieke token voor resource namen')
param resourceToken string

@description('Tags voor alle resources')
param tags object = {}

@description('Resource ID van de Log Analytics workspace')
param workspaceId string

// ============================================================
// Data Collection Endpoint
// ============================================================
resource dataCollectionEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2023-03-11' = {
  name: 'dce-defender-dashboard-${resourceToken}'
  location: location
  tags: tags
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

// ============================================================
// DCR: Dagelijkse Scores (Exposure, Secure, Config, Recommendations, Alerts)
// ============================================================
resource dcrDailyScores 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-defender-daily-scores-${resourceToken}'
  location: location
  tags: tags
  properties: {
    dataCollectionEndpointId: dataCollectionEndpoint.id
    streamDeclarations: {
      'Custom-DefenderExposureScore_CL': {
        columns: [
          { name: 'TimeGenerated', type: 'datetime' }
          { name: 'ExposureScore', type: 'real' }
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
      'Custom-DefenderSecureScoreControls_CL': {
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
      'Custom-DefenderConfigurationScore_CL': {
        columns: [
          { name: 'TimeGenerated', type: 'datetime' }
          { name: 'ConfigurationScore', type: 'real' }
        ]
      }
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
      'Custom-DefenderASREvents_CL': {
        columns: [
          { name: 'TimeGenerated', type: 'datetime' }
          { name: 'RuleName', type: 'string' }
          { name: 'ActionType', type: 'string' }
          { name: 'EventCount', type: 'int' }
          { name: 'UniqueDevices', type: 'int' }
        ]
      }
      'Custom-DefenderProtectionState_CL': {
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
      'Custom-DefenderAVOutdated_CL': {
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
      'Custom-DefenderAVDetections_CL': {
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
        streams: [ 'Custom-DefenderExposureScore_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderExposureScore_CL'
      }
      {
        streams: [ 'Custom-DefenderSecureScore_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderSecureScore_CL'
      }
      {
        streams: [ 'Custom-DefenderSecureScoreControls_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderSecureScoreControls_CL'
      }
      {
        streams: [ 'Custom-DefenderConfigurationScore_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderConfigurationScore_CL'
      }
      {
        streams: [ 'Custom-DefenderAlertAggregates_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderAlertAggregates_CL'
      }
      {
        streams: [ 'Custom-DefenderRecommendations_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderRecommendations_CL'
      }
      {
        streams: [ 'Custom-DefenderASREvents_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderASREvents_CL'
      }
      {
        streams: [ 'Custom-DefenderProtectionState_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderProtectionState_CL'
      }
      {
        streams: [ 'Custom-DefenderAVOutdated_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderAVOutdated_CL'
      }
      {
        streams: [ 'Custom-DefenderAVDetections_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderAVDetections_CL'
      }
    ]
  }
}

// ============================================================
// DCR: Wekelijkse Snapshots (Device, Software, AV, Config, Vuln)
// ============================================================
resource dcrWeeklySnapshots 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-defender-weekly-snapshots-${resourceToken}'
  location: location
  tags: tags
  properties: {
    dataCollectionEndpointId: dataCollectionEndpoint.id
    streamDeclarations: {
      'Custom-DefenderDeviceInventory_CL': {
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
        streams: [ 'Custom-DefenderDeviceInventory_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderDeviceInventory_CL'
      }
      {
        streams: [ 'Custom-DefenderSoftwareInventory_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderSoftwareInventory_CL'
      }
      {
        streams: [ 'Custom-DefenderAVHealth_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderAVHealth_CL'
      }
      {
        streams: [ 'Custom-DefenderSecureConfig_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderSecureConfig_CL'
      }
      {
        streams: [ 'Custom-DefenderVulnDelta_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderVulnDelta_CL'
      }
      {
        streams: [ 'Custom-DefenderDeviceSoftware_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-DefenderDeviceSoftware_CL'
      }
    ]
  }
}

// ============================================================
// DCR: Intune Data
// ============================================================
resource dcrIntune 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-defender-intune-${resourceToken}'
  location: location
  tags: tags
  properties: {
    dataCollectionEndpointId: dataCollectionEndpoint.id
    streamDeclarations: {
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
          { name: 'UserDisplayName', type: 'string' }
          { name: 'IsEncrypted', type: 'boolean' }
          { name: 'Model', type: 'string' }
          { name: 'Manufacturer', type: 'string' }
          { name: 'EnrolledDateTime', type: 'datetime' }
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
        streams: [ 'Custom-IntuneDevices_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-IntuneDevices_CL'
      }
      {
        streams: [ 'Custom-IntuneDetectedApps_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-IntuneDetectedApps_CL'
      }
      {
        streams: [ 'Custom-IntuneComplianceReports_CL' ]
        destinations: [ 'defender-dashboard-workspace' ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-IntuneComplianceReports_CL'
      }
    ]
  }
}

// ============================================================
// Outputs
// ============================================================
@description('Data Collection Endpoint URI')
output dceEndpoint string = dataCollectionEndpoint.properties.logsIngestion.endpoint

@description('Data Collection Endpoint ID')
output dceId string = dataCollectionEndpoint.id

@description('DCR Daily Scores — Immutable ID')
output dcrDailyScoresImmutableId string = dcrDailyScores.properties.immutableId

@description('DCR Daily Scores — Resource ID')
output dcrDailyScoresId string = dcrDailyScores.id

@description('DCR Weekly Snapshots — Immutable ID')
output dcrWeeklySnapshotsImmutableId string = dcrWeeklySnapshots.properties.immutableId

@description('DCR Weekly Snapshots — Resource ID')
output dcrWeeklySnapshotsId string = dcrWeeklySnapshots.id

@description('DCR Intune — Immutable ID')
output dcrIntuneImmutableId string = dcrIntune.properties.immutableId

@description('DCR Intune — Resource ID')
output dcrIntuneId string = dcrIntune.id
