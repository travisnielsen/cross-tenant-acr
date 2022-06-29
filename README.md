# Container Registry Cross Tenant Sample

This sample shows how to promote images across AAD tenants where registries have network security enabled.

## Deployment

Ensure you have updated versions of PowerShell and Azure CLI installed on your workstation.

### Contoso Environment

 Next, open a console session and navigate the `deployment` directory. Run the following commands to deploy the Contoso environment:

```powershell
az group create --name contoso-acrdemo --location centralus
az bicep build -f contosoinfra.bicep
az deployment group create --resource-group contoso-acrdemo --name demo2 --template-file contosoinfra.json
```

Use Bastion to connect to the virtual machine and install Docker:

```bash
sudo apt-get update
sudo apt install docker.io -y
sudo docker run -it hello-world
```

Next, install the Azure CLI:

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

### Fabrikam Environment

Switch your Azure CLI context to the Fabrikam tenant and run the folllowing to deploy the Container Registry instance.

```powershell
az account set --subscription [tenant_2_subscription_guid]
az group create --name fabrkiam-acrdemo --location centralus
az bicep build -f fabrikaminfra.bicep
az deployment group create --resource-group fabrikam-acrdemo --name demo --template-file fabrikaminfra.json
```

Upload an image to the container registry.

**NOTE:** You must have a recent version of Docker CLI running from your workstation when doing this.

```bash
az acr login --name [registryname]
docker pull mcr.microsoft.com/hello-world
docker tag mcr.microsoft.com/hello-world [registryname].azurecr.io/hello-world:v1
docker push <login-server>/hello-world:v1
```

## Testing

From the build server, get the current IP address:

```bash
curl https://ipinfo.io/ip
```

Add the public IP to the netowrk ACL of the Fabrikam Container registry via **Networking > Public access > Firewall**. Be sure to click **Save** when the public IP is added

From the build server, import the container image from Fabricam to Contoso using the instructions outlined here: [Cross-tenant import with access token](https://docs.microsoft.com/en-us/azure/container-registry/container-registry-import-images?tabs=azure-cli#cross-tenant-import-with-access-token). Example:

```bash
# Sign into the Fabrkiam tenant and get access token
az login --service-principal --username [appId] --password [password]  --tenant [tenantId]
az account get-access-token

# Sign into the Contoso tenant and run the import task using the access token
az logout
az login --identity
az acr login --name [registryname]
az acr import --name [contoso-acr-name] --source [fabrikam-acr-name].azurecr.io/hello-world:v1 --image hello-world-imported:v1 --password [access-token]
```
