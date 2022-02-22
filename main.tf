terraform {
  required_version = ">=0.12"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>2.0"
    }
  }
}

# Configure the Azure provider
provider "azurerm" {
  features {}
}

# Create AND Digital Technical Test resource group
resource "azurerm_resource_group" "ttest" {
  name     = var.resource_group_name
  location = var.location
}

# Generate random string for the domain name
resource "random_string" "fqdn" {
  length  = 6
  special = false
  upper   = false
  number  = false
}

# Create virtual network
resource "azurerm_virtual_network" "ttest" {
  name                = "ttest-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.ttest.name
}

# Create subnet
resource "azurerm_subnet" "ttest" {
  name                 = "ttest-subnet"
  resource_group_name  = azurerm_resource_group.ttest.name
  virtual_network_name = azurerm_virtual_network.ttest.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Create public IP adress for the Load Balancer
resource "azurerm_public_ip" "ttest" {
  name                = "ttest-public-ip"
  location            = var.location
  resource_group_name = azurerm_resource_group.ttest.name
  allocation_method   = "Static"
  domain_name_label   = random_string.fqdn.result
}

# Create Load Balancer
resource "azurerm_lb" "ttest" {
  name                = "ttest-lb"
  location            = var.location
  resource_group_name = azurerm_resource_group.ttest.name

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.ttest.id
  }
}

# Manages Load Balancer Backend Address Pool
resource "azurerm_lb_backend_address_pool" "bpepool" {
  loadbalancer_id = azurerm_lb.ttest.id
  name            = "BackEndAddressPool"
}

#Manages Load Balancer Probe Resource
resource "azurerm_lb_probe" "ttest" {
  resource_group_name = azurerm_resource_group.ttest.name
  loadbalancer_id     = azurerm_lb.ttest.id
  name                = "ssh-running-probe"
  port                = var.application_port
}

#Manages Load Balancer Rule
resource "azurerm_lb_rule" "lbnatrule" {
  resource_group_name            = azurerm_resource_group.ttest.name
  loadbalancer_id                = azurerm_lb.ttest.id
  name                           = "http"
  protocol                       = "Tcp"
  frontend_port                  = var.application_port
  backend_port                   = var.application_port
  backend_address_pool_id        = azurerm_lb_backend_address_pool.bpepool.id
  frontend_ip_configuration_name = "PublicIPAddress"
  probe_id                       = azurerm_lb_probe.ttest.id
}

# Create Linux virtual machine scale set and attach it to the network
resource "azurerm_virtual_machine_scale_set" "ttest" {
  name                = "vmscaleset"
  location            = var.location
  resource_group_name = azurerm_resource_group.ttest.name
  upgrade_policy_mode = "Manual"


  sku {
    name     = "Standard_DS1_v2"
    tier     = "Standard"
    capacity = 2
  }

  storage_profile_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  storage_profile_os_disk {
    name              = ""
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_profile_data_disk {
    lun           = 0
    caching       = "ReadWrite"
    create_option = "Empty"
    disk_size_gb  = 10
  }

  os_profile {
    computer_name_prefix = "vmlab"
    admin_username       = var.admin_user
    admin_password       = var.admin_password
    custom_data          = file("web.conf")
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  network_profile {
    name    = "terraformnetworkprofile"
    primary = true

    ip_configuration {
      name                                   = "IPConfiguration"
      subnet_id                              = azurerm_subnet.ttest.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.bpepool.id]
      primary                                = true
    }
  }
}

# Create Autoscale  moniter
resource "azurerm_monitor_autoscale_setting" "ttest" {
  name                = "AutoscaleSetting"
  resource_group_name = azurerm_resource_group.ttest.name
  location            = var.location
  target_resource_id  = azurerm_virtual_machine_scale_set.ttest.id

  profile {
    name = "defaultProfile"

    capacity {
      default = 2
      minimum = 1
      maximum = 10
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_virtual_machine_scale_set.ttest.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 75
        metric_namespace   = "microsoft.compute/virtualmachinescalesets"
        dimensions {
          name     = "AppName"
          operator = "Equals"
          values   = ["App1"]
        }
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_virtual_machine_scale_set.ttest.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }
  }
}