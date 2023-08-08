param orgName string
param location string = resourceGroup().location

#disable-next-line prefer-unquoted-property-names
var locationMap = { 'westeurope': 'we', 'northeurope': 'ne', 'germanynorth': 'gn', 'germanywestcentral': 'gwc' }
var locationString = locationMap[location]

var appName = 'vcsl'
var functionSyncAppName = 'func-${orgName}-${appName}sync-${locationString}-001'
var functionDownloadAppName = 'func-${orgName}-${appName}download-${locationString}-001'
var storageAccountName = 'sa${orgName}${appName}'
var appServicePlan = 'asp-${appName}-${locationString}-001'
var applicationInsightsName = 'appi-${appName}-${locationString}-001'

var functionWorkerRuntime = 'dotnet'
var netFrameworkVersion = '6.0'

resource vCardstorageaccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    allowBlobPublicAccess: false
  }
}

resource apphostingPlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlan
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {}
}

resource vCardSyncFunctionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionSyncAppName
  kind: 'functionapp'
  location: location
  dependsOn: [
#disable-next-line no-unnecessary-dependson
    vCardstorageaccount
  ]
  properties: {
    httpsOnly: true
    serverFarmId: apphostingPlan.id
    siteConfig: {
      publicNetworkAccess: 'Enabled'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${vCardstorageaccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${vCardstorageaccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: '${toLower(functionSyncAppName)}-content'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~14'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionWorkerRuntime
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
      netFrameworkVersion: netFrameworkVersion
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
    }
  }
}

resource vCardDownloadFunctionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionDownloadAppName
  kind: 'functionapp'
  location: location
  dependsOn: [
#disable-next-line no-unnecessary-dependson
    vCardstorageaccount
  ]
  properties: {
    httpsOnly: true
    serverFarmId: apphostingPlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${vCardstorageaccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${vCardstorageaccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: '${toLower(functionDownloadAppName)}-content'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~14'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionWorkerRuntime
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
      netFrameworkVersion: netFrameworkVersion
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
    }
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
  }
}

resource appSyncConnectionString 'Microsoft.Web/sites/config@2022-09-01' = {
  name: 'web'
  kind: 'string'
  parent: vCardSyncFunctionApp
  properties: {
    connectionStrings: [
      {
        connectionString: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${vCardstorageaccount.listKeys().keys[0].value}'
        name: 'VCSLStorage'
        type: 'Custom'
      } ]
  }
}

resource appDownConnectionString 'Microsoft.Web/sites/config@2022-09-01' = {
  name: 'web'
  kind: 'string'
  parent: vCardDownloadFunctionApp
  properties: {
    connectionStrings: [
      {
        connectionString: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${vCardstorageaccount.listKeys().keys[0].value}'
        name: 'VCSLStorage'
        type: 'Custom'
      } ]
  }
}
