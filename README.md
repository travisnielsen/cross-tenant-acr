# Container Registry Cross Tenant Sample

This sample shows how to promote images across AAD tenants where registries have network security enabled.

## Deployment

Ensure you have updated versions of PowerShell and Azure CLI installed on your workstation.

### Contoso Environment

 Next, open a console session and navigate the `deployment` directory. Run the following commands to deploy the Contoso environment:

```powershell
az group create --name contoso-acrdemo --location centralus
az bicep build -f contosoinfra.bicep
az deployment group create --resource-group contoso-acrdemo --name demo --template-file contosoinfra.json
```

### Fabrikam Environment

Switch your Azure CLI context to the Fabrikam tenant and run the folllowing to deploy the Container Registry instance.

```powershell
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

Use Bastion to connect to the virtual machine and install the Azure CLI:

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```
