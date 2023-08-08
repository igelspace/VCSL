param appName string
param envir string
param location string = resourceGroup().location
param funcSyncZipUri string
param funcDownloadZipUri string

var storageAccountName      = 'sa${appName}01'
var syncFunctionAppName     = 'func-${envir}-${appName}sync-${location}-001'
var downloadFunctionAppName = 'func-${envir}-${appName}download-${location}-001'
var appServicePlanName      = 'asp-${appName}-${location}-001'
var appInsightsName         = 'appi-${appName}-${location}-001'

var functionWorkerRuntime   = 'dotnet'

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties:{
    allowBlobPublicAccess: false
  }  
}

resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {}
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
  }
}

resource syncFunctionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: syncFunctionAppName
  kind: 'functionapp'
  location:location
  properties: {
    httpsOnly: true
    serverFarmId: appServicePlan.id
    siteConfig:{
      publicNetworkAccess: 'Enabled'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(appName)
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
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
    }
   
  }
}

resource downloadFunctionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: downloadFunctionAppName
  kind: 'functionapp'
  location:location
  properties: {
    httpsOnly: true
    serverFarmId: appServicePlan.id
    siteConfig:{
      publicNetworkAccess: 'Enabled'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(appName)
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
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
    }
   
  }
}

resource appSyncConnectionString 'Microsoft.Web/sites/config@2022-09-01' = {
  name:'web'
  kind:'string'
  parent:syncFunctionApp
  properties:{
    connectionStrings: [
      {
        connectionString: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        name: 'VCSLStorage'
        type:'Custom'
      }]
  }
}

resource appDownloadConnectionString 'Microsoft.Web/sites/config@2022-09-01' = {
  name:'web'
  kind:'string'
  parent:downloadFunctionApp
  properties:{
    connectionStrings: [
      {
        connectionString: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        name: 'VCSLStorage'
        type:'Custom'
      }]
  }
}

// resource syncZipDeploy 'Microsoft.Web/sites/extensions@2022-03-01' = {
//   parent: syncFunctionApp
//   name: 'MSDeploy'
//   properties: {
//     packageUri: funcSyncZipUri
//   }
// }

// resource downloadZipDeploy 'Microsoft.Web/sites/extensions@2022-03-01' = {
//   parent: downloadFunctionApp
//   name: 'MSDeploy'
//   properties: {
//     packageUri: funcDownloadZipUri
//   }
// }
