terraform {
  required_version = "=0.15.1"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=2.89.0"
    }
    tls     = {
      source  = "hashicorp/tls"
      version = ">=3.1.0"
    }
    random  = {
      source  = "hashicorp/random"
      version = ">=3.1.0"
    }
    local   = {
      source  = "hashicorp/local"
      version = ">=2.1.0"
    }
  }
}

provider "random" {}

resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "_%@"
}

resource "random_id" "id" {
  byte_length = 8
}

locals {
  vm_name            = "ml-jumphost"
  vm_name_full       = "${local.vm_name}-${random_id.id.hex}"
  vm_size            = "Standard_B1ls"
  admin_user         = var.admin_user != "" ? var.admin_user : "mladmin"
  public_ip_required = true
  model_name         = "weekdays.py"
  model_data         = <<-EOT
    weekdays = ["Sunday", "Monday", "Tuesday","Wednesday", "Thursday","Friday", "Saturday"]
    print("Seven Weekdays are:\n")
    for day in range(len(weekdays)):
      print(weekdays[day])
    EOT

  vm_image = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }

  tags = {
    Name  = local.vm_name_full
    ID    = random_id.id.hex
    Owner = "DND"
  }
}

provider "tls" {}

resource "tls_private_key" "ssh-key" {
  count     = var.admin_public_key == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

provider "local" {}

resource "local_file" "private-key-file" {
  count           = var.admin_public_key == "" ? 1 : 0
  content         = tls_private_key.ssh-key[0].private_key_pem
  filename        = "${local.vm_name_full}.pem"
  file_permission = "0600"
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "m3-rg-${random_id.id.hex}"
  location = var.location

  tags = local.tags
}

resource "azurerm_public_ip" "pip" {
  count               = local.public_ip_required ? 1 : 0
  name                = "ip-pub-${random_id.id.hex}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"

  tags = local.tags
}

resource "azurerm_virtual_network" "vnet" {
  name                = "virtual-net-${random_id.id.hex}"
  address_space       = [
    "10.10.0.0/16"
  ]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  tags = local.tags
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-${random_id.id.hex}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [
    "10.10.10.0/24"
  ]
}

resource "azurerm_network_interface" "nic" {
  name                = "nic-${random_id.id.hex}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ip-int-${random_id.id.hex}"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = local.public_ip_required ? azurerm_public_ip.pip[0].id : null
  }

  tags = local.tags
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                            = "vm-${random_id.id.hex}"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  computer_name                   = local.vm_name
  size                            = local.vm_size
  admin_username                  = var.admin_user
  admin_password                  = random_password.password.result
  disable_password_authentication = false
  custom_data                     = base64encode(templatefile("${path.module}/cloud-init.yml", {
    subscription_id = var.subscription_id,
    model_name      = local.model_name,
    model_data      = base64encode(local.model_data)
  }))

  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  admin_ssh_key {
    username   = var.admin_user
    public_key = var.admin_public_key != "" ? var.admin_public_key : tls_private_key.ssh-key[0].public_key_openssh
  }

  os_disk {
    name                 = "os-disk-${random_id.id.hex}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = local.vm_image.publisher
    offer     = local.vm_image.offer
    sku       = local.vm_image.sku
    version   = local.vm_image.version
  }

  tags = local.tags
}

resource "azurerm_network_security_group" "sg" {
  name                = "sg-${random_id.id.hex}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  security_rule {
    name                       = "ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "http"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "https"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = local.tags
}

data "azurerm_subscription" "current" {}
