param location string = resourceGroup().location
param acrManagedIdentityName string = 'contosoacr'

var natGatewayIpName = '${uniqueString(resourceGroup().id)}-natgw'
var bastionIpName = '${uniqueString(resourceGroup().id)}-bastion'
var natGatewayName = uniqueString(resourceGroup().id)
var vnetName = uniqueString(resourceGroup().id)
var bastionName = uniqueString(resourceGroup().id)
var acrName = uniqueString(resourceGroup().id)
var buildServerName = uniqueString(resourceGroup().id)
var acrPrivateDnsZoneName = 'privatelink.azurecr.io'
var keyVaultName = uniqueString(resourceGroup().id)

///
/// IDENTITY
///

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: acrManagedIdentityName
  location: location
}

///
/// NETWORKING
///

resource natGatewayIP 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: natGatewayIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
  }
}

resource bastionIP 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: bastionIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
}

resource natgateway 'Microsoft.Network/natGateways@2021-05-01' = {
  name: natGatewayName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 4
    publicIpAddresses: [
      {
        id: natGatewayIP.id
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2020-06-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.0.0.0/24' // 10.0.0.0 - 10.0.0.255
        }
      }
      {
        name: 'buildservers'
        properties: {
          addressPrefix: '10.0.1.0/24' // 10.0.1.0 - 10.0.1.255
          natGateway: {
            id: natgateway.id
          }
        }
      }
      {
        name: 'services'
        properties: {
          addressPrefix: '10.0.2.0/24' // 10.0.2.0 - 10.0.2.255
        }
      }
      {
        name: 'agents'
        properties: {
          addressPrefix: '10.0.3.0/24' // 10.0.3.0 - 10.0.3.255
          natGateway: {
            id: natgateway.id
          }
        }
      }
    ]
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2020-06-01' = {
  name: bastionName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'bastionConf'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/AzureBastionSubnet'
          }
          publicIPAddress: {
            id: bastionIP.id
          }
        }
      }
    ]
  }
}

///
/// CONTAINER REGISTRY
///

resource acrDnsZone 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: acrPrivateDnsZoneName
  location: 'global'
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
  name: '${acrPrivateDnsZoneName}/${vnetName}-link'
  dependsOn: [ acrDnsZone ]
  location: 'global'
  properties: {
     registrationEnabled: true
      virtualNetwork: {
        id: vnet.id
      }
  }
}

resource acr 'Microsoft.ContainerRegistry/registries@2022-02-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Premium'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    adminUserEnabled: false
    networkRuleBypassOptions: 'AzureServices'
    publicNetworkAccess: 'Disabled'
  }
}

resource acrAgents 'Microsoft.ContainerRegistry/registries/agentPools@2019-06-01-preview' = {
  name:'${acrName}-agents'
  location: location
  parent: acr
  properties: {
    count: 1
    os: 'Linux'
    tier: 'S1'
    virtualNetworkSubnetResourceId: vnet.properties.subnets[3].id
  }
}

var subscriptionId = subscription().subscriptionId
var privateEndpointName = '${acr.name}-endpoint'
var subnetId = resourceId(subscriptionId, resourceGroup().name, 'Microsoft.Network/virtualNetworks/subnets', vnetName, 'services')
var dnsZoneId = resourceId(subscriptionId, resourceGroup().name, 'Microsoft.Network/privateDnsZones', acrPrivateDnsZoneName )

resource acrPrivateEndpoint 'Microsoft.Network/privateEndpoints@2020-06-01' = {
  name: privateEndpointName
  location: location
  dependsOn: [
    privateDnsZoneLink
  ]
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: privateEndpointName
        properties: {
          privateLinkServiceId: acr.id
          groupIds: [
            'registry'
          ]
        }
      }
    ]
  }
}

resource privateDnsZoneConfig 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-06-01' = {
  name: '${privateEndpointName}/dnsgroupname'
  dependsOn: [
    acrPrivateEndpoint
  ]
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: dnsZoneId
        }
      }
    ]
  }
}


///
/// PRIVATE BUILD SERVER
///

@description('Username for the Virtual Machine.')
param adminUsername string

@description('Password for the Virtual Machine.')
@secure()
param adminPasswordOrKey string

@description('The Ubuntu version for the VM. This will pick a fully patched image of this given Ubuntu version.')
@allowed([
  '18.04-LTS'
])
param ubuntuOSVersion string = '18.04-LTS'

@description('The size of the VM')
param vmSize string = 'Standard_B2s'

var osDiskType = 'Standard_LRS'

resource buildserver 'Microsoft.Compute/virtualMachines@2022-03-01' = {
  name: buildServerName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: osDiskType
        }
      }
      imageReference: {
        publisher: 'Canonical'
        offer: 'UbuntuServer'
        sku: ubuntuOSVersion
        version: 'latest'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    osProfile: {
      computerName: buildServerName
      adminUsername: adminUsername
      adminPassword: adminPasswordOrKey
      linuxConfiguration: null
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2021-05-01' = {
  name: '${buildServerName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vnet.properties.subnets[1].id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}


///
/// KEY VAULT
///

@description('Password for Fabrikan Service Principal')
@secure()
param fabrikamPassword string

resource akv 'Microsoft.KeyVault/vaults@2021-11-01-preview' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    createMode: 'default'
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    tenantId: subscription().tenantId
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }

  }
}

resource secret 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  name: 'fabrikamaccount'
  parent: akv
  properties: {
    value: fabrikamPassword
    attributes: {
      enabled: true
    }
  }
}

///
/// RBAC
///

// See: https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles

// Grant read Key Vault secrets to the user-assigned managed identity  

var roleDefinitionIdAkvSecretsUser = '4633458b-17de-408a-b874-0445c86b69e6'

resource akvSecretsAccess 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  scope: akv
  name: guid(resourceGroup().id, managedIdentity.id, roleDefinitionIdAkvSecretsUser)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionIdAkvSecretsUser)
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}


// Grant ACR push / pull to build VM

var roleDefinitionIdAcrPush = '8311e382-0749-4cb8-b61a-304f252e45ec'
var roleDefinitionIdAcrPull = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var roleDefinitionIdRead = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'

resource acrPushPushAccess 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  scope: acr
  name: guid(resourceGroup().id, managedIdentity.id, roleDefinitionIdAcrPush)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionIdAcrPush)
    principalId: buildserver.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource acrPullAccess 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  scope: acr
  name: guid(resourceGroup().id, managedIdentity.id, roleDefinitionIdAcrPull)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionIdAcrPull)
    principalId: buildserver.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource acrReadAccess 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  scope: acr
  name: guid(resourceGroup().id, managedIdentity.id, roleDefinitionIdRead)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionIdRead)
    principalId: buildserver.identity.principalId
    principalType: 'ServicePrincipal'
  }
}
