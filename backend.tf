terraform {
  backend "azurerm" {
    resource_group_name  = "rg-gav2022-gslim"
    storage_account_name = "stagav2022"
    container_name       = "gav2022contain"
    key                  = "tfstate"
  }
}