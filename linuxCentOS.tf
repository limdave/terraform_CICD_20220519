# This is create a CentOS linux VM and install http
# Updated 2022.05.19 limgong

# Declare of the Provider
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "~>2.0"                 #2.99.0
    }
  }
    # Use backed locally first. Commenting out this after configuring remote backend.
    #backend "local" {
    #  path = "./terraform.tfstate"
    #} 
}
provider "azurerm" {
  features {}
}

# Declare of the Create Date and KST Time
locals {
    current_time = formatdate("YYYY.MM.DD HH:mmAA",timeadd(timestamp(),"9h"))
}

output "current_time" {
    value = local.current_time
}

# Create a resource group if it doesn't exist
# Must change rg-name and location 
resource "azurerm_resource_group" "ggResourcegroup" {
    #name     = "rg-eus-test11"
    #location = "eastus"
    name     = var.resource_group_name
    location = var.location
    #tags = var.default_tags
    tags    = {
        envrionment = "test"
        datetime = "${local.current_time}"
        owner   = "gslim"
    }
}

# Create virtual networks
# Azure assigns private IP addresses to resources from the address range of the [10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16]
resource "azurerm_virtual_network" "ggVnet01" {
    name                = "vnet-eus-spoke01"
    address_space       = ["10.50.1.0/24"]
    location            = azurerm_resource_group.ggResourcegroup.location
    resource_group_name = azurerm_resource_group.ggResourcegroup.name

    tags    = var.default_tags
}

# Create subnet
resource "azurerm_subnet" "ggSubnet00" {
    name                 = "subnet-spoke01-00"
    resource_group_name  = azurerm_resource_group.ggResourcegroup.name
    virtual_network_name = azurerm_virtual_network.ggVnet01.name
    address_prefixes       = ["10.50.1.0/26"]
    tags    = var.default_tags
}

# Create public IPs
resource "azurerm_public_ip" "ggPublicIP" {
    count = 1
    name                         = "VM-centos${count.index}-pip"
    location                     = azurerm_resource_group.ggResourcegroup.location
    resource_group_name          = azurerm_resource_group.ggResourcegroup.name
    #allocation_method            = "Dynamic"           #Dynamic 이면 IP주소 표시 안됨
    allocation_method            = "Static"

    tags    = var.default_tags
}

# Create network interface
resource "azurerm_network_interface" "ggNic" {
    count = 1
    name                      = "VM-centos-NIC${count.index}"
    location                  = azurerm_resource_group.ggResourcegroup.location
    resource_group_name       = azurerm_resource_group.ggResourcegroup.name

    ip_configuration {
        name                          = "ggNic${count.index}Configuration"
        subnet_id                     = azurerm_subnet.ggSubnet00.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.ggPublicIP[count.index].id
    }

    tags    = var.default_tags
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "ggNsg" {
    name                = "nsg-vnet01Subnet00"
    location            = azurerm_resource_group.ggResourcegroup.location
    resource_group_name = azurerm_resource_group.ggResourcegroup.name

    security_rule {
        name                       = "HTTP"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "80"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    security_rule {
        name                       = "SSH"
        priority                   = 1002
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"      #After create, assign a source ip address
        destination_address_prefix = "*"
    }
    tags = var.default_tags
}


# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "ggnicasso" {
    count = 1
    network_interface_id      = azurerm_network_interface.ggNic[count.index].id
    network_security_group_id = azurerm_network_security_group.ggNsg.id
}

data "azurerm_client_config" "current" {}

# Pull existing Key Vault from Azure
data "azurerm_key_vault" "kv" {
  name                = var.kv_name
  resource_group_name = var.kv_rgname
}

data "azurerm_key_vault_secret" "kv_secret" {
  name         = var.kv_secretname
  key_vault_id = data.azurerm_key_vault.kv.id
}

# Create (and display) an SSH key
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}


# Create linux virtual machine
resource "azurerm_linux_virtual_machine" "gglinuxVM" {
    count = 1
    name                  = "VM-centos-${count.index}"
    location              = azurerm_resource_group.ggResourcegroup.location
    resource_group_name   = azurerm_resource_group.ggResourcegroup.name
    network_interface_ids = [azurerm_network_interface.ggNic[count.index].id]
    size                  = "Standard_D2s_v5"

    os_disk {
        name              = "ggOsDisk${count.index}"
        caching           = "ReadWrite"
        storage_account_type = "StandardSSD_LRS"
    }
    
    source_image_reference {
        publisher = "OpenLogic"
        offer     = "CentOS"
        sku       = "7_9-gen2"     #7_9-gen2 on eastus
        version   = "latest"
    }
    /*
    admin_ssh_key {
        username   = var.admin_username
        public_key = file("~/.ssh/id_rsa.pub")
    }
    */
    admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh.public_key_openssh
    }
    
    /*
    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "20.04-LTS"
        version   = "latest"
    }
    */
    computer_name  = "ggvm-${count.index}"
    admin_username = "ggadm"
    #admin_password = var.admin_password
    disable_password_authentication = false
    #custom_data = filebase64("./apache.sh")
    admin_password                  = data.azurerm_key_vault_secret.kv_secret.value
    custom_data = base64encode(data.template_file.linux-vm-http.rendered)

    #boot_diagnostics {
    #    storage_account_uri = azurerm_storage_account.ggstorageaccount.primary_blob_endpoint
    #}

    tags    = var.default_tags
}

# Template for bootstrapping
data "template_file" "linux-vm-http" {
  template = file("azure_user_data.sh")
}

### Display output Linux Vm information
/*
output "VM-Linux-PublicIP" { 
    value = azurerm_public_ip.ggPublicIP.ip_address
}
*/

/*
# Generate random text for a unique storage account name
resource "random_id" "randomId" {
    keepers = {
        # Generate a new ID only when a new resource group is defined
        resource_group = azurerm_resource_group.myterraformgroup.name
    }

    byte_length = 8
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "mystorageaccount" {
    name                        = "diag${random_id.randomId.hex}"
    resource_group_name         = azurerm_resource_group.myterraformgroup.name
    location                    = "eastus"
    account_tier                = "Standard"
    account_replication_type    = "LRS"

    tags = var.default_tags
}
*/
