# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.12, < 5.0"
    }
  }
}

provider "azurerm" {
  features {}
}