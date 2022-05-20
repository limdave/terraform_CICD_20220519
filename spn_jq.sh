#Create an Azure service principal:
SERVICE_PRINCIPAL_NAME=spn_gslim
SERVICE_PRINCIPAL=$(az ad sp create-for-rbac --name $SERVICE_PRINCIPAL_NAME)
 
#sp name result :
{
  "appId": "09ca0336-927c-4e56-8a4a-36063ced3441",
  "displayName": "spn-gslim",
  "password": "A4srViytp~s-lX3hGAdERjj4Jw4MikByYE",
  "tenant": "6144959d-620b-4d3d-9090-c4891f1914ce"
}

#Run the following commands to fill the credentials variables:
CLIENT_ID=$(echo $SERVICE_PRINCIPAL | jq -r .appId)
CLIENT_SECRET=$(echo $SERVICE_PRINCIPAL | jq -r .password)
TENANT_ID=$(echo $SERVICE_PRINCIPAL | jq -r .tenant)
SUBSCRIPTION_ID=$(az account show | jq -r .id)
SUBSCRIPTION_NAME=$(az account show | jq -r .name)

