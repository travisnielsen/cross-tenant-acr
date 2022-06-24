param location string = resourceGroup().location

var vnetName = uniqueString(resourceGroup().id)
var bastionName = uniqueString(resourceGroup().id)
var acrName = uniqueString(resourceGroup().id)
var buildServerName = uniqueString(resourceGroup().id)
var acrPrivateDnsZoneName = 'privatelink.azurecr.io'

///
/// NETWORKING
///

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
        }
      }
      {
        name: 'services'
        properties: {
          addressPrefix: '10.0.2.0/24' // 10.0.2.0 - 10.0.2.255
        }
      }
    ]
  }
}

resource bastionIP 'Microsoft.Network/publicIPAddresses@2020-06-01' = {
  name: bastionName
  location: location
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
  sku: {
    name: 'Standard'
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
/// BUILD SERVER
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
