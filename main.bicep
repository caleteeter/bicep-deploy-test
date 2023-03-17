@description('Azure region that will be targeted for resources.')
param location string = resourceGroup().location

@description('RPC enabled')
param rpcEnabled bool = false

@description('Indexer enabled')
param indexerEnabled bool = false

// this is used to ensure uniqueness to naming (making it non-deterministic)
param rutcValue string = utcNow()

// the built-in role that allow contributor permissions (create)
// NOTE: there is no built-in creator/contributor role 
var roleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: '${uniqueString(resourceGroup().id)}mi'
  location: location
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  #disable-next-line use-stable-resource-identifiers simplify-interpolation
  name: '${guid(uniqueString(resourceGroup().id), rutcValue)}'
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
    description: 'akvrole'
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource akv 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: 'a${uniqueString(resourceGroup().id)}akv'
  location: location
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    accessPolicies: [
      {
        objectId: managedIdentity.properties.principalId
        tenantId: managedIdentity.properties.tenantId
        permissions: {
          secrets: [
            'all'
          ]
        }
      }
    ]
  }
}

resource deploymentScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${uniqueString(resourceGroup().id)}dpy'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities:{
      '${managedIdentity.id}': {}
    }
  }
  
  properties: {
    arguments: '${managedIdentity.id} ${akv.name} ${(rpcEnabled ? 2 : 0)} ${(indexerEnabled ? 2 : 0)}'
    forceUpdateTag: '1'
    containerSettings: {
      containerGroupName: '${uniqueString(resourceGroup().id)}ci1'
    }
    primaryScriptUri: 'https://raw.githubusercontent.com/caleteeter/polygon-azure/main/scripts/deploy.sh'
    timeout: 'PT30M'
    cleanupPreference: 'OnSuccess'
    azCliVersion: '2.28.0'
    retentionInterval: 'P1D'
  }
}
