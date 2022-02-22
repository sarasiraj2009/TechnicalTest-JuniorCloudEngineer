variable "resource_group_name" {
  description = "Name of the resource group in which the resources will be created"
  default     = "ANDD-ttest"
}

variable "location" {
  default     = "eastus"
  description = "Location where resources will be created"
}


variable "application_port" {
  description = "Port that you want to expose to the external load balancer"
  default     = 80
}

variable "admin_user" {
  description = "User name to use as the admin account on the VMs that will be part of the VM scale set"
  default     = "azureuser"
}

variable "admin_password" {
  description = "Default password for admin account"
  default     = "userAdmin123@"
}