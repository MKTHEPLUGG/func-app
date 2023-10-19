@description('The name of the project')
param projectName string = 'et'

@description('User sequence number')
param userSequenceNumber int

@description('Location for all resources.')
param location string = resourceGroup().location

var resourceAbbreviations = {
  ai: 'application-insights'
  asp: 'app-service-plan'
  sta: 'storageaccount'
  fa: 'function-app'
}

var names = {
  aiName: '${projectName}-${userSequenceNumber}-${resourceAbbreviations.ai}-009'
  aspName: '${projectName}-${userSequenceNumber}-${resourceAbbreviations.asp}-009'
  staName: '${projectName}${userSequenceNumber}${resourceAbbreviations.sta}009'
  faName: '${projectName}-${userSequenceNumber}-${resourceAbbreviations.fa}-009'
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: names.staName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'Storage'
  properties: {
    supportsHttpsTrafficOnly: true
    defaultToOAuthAuthentication: true
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2021-03-01' = {
  name: names.aspName
  location: location
  sku: {
    name: 'Free'
  }
  properties: {}
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: names.aiName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
  }
}

resource functionApp 'Microsoft.Web/sites@2021-03-01' = {
  name: names.faName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(names.faName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'powershell'
        }
      ]
    }
    httpsOnly: true
  }
}
