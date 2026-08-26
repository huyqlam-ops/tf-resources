# Lấy Client ID / Identity đang thực thi Terraform
data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "rg" {
  name     = "rg-training-microservices"
  location = "East Asia"
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

module "storage" {
  source              = "./modules/storage"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  suffix              = random_string.suffix.result
}

module "event_hub" {
  source              = "./modules/event_hub"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  suffix              = random_string.suffix.result
}

module "cosmos_db" {
  source              = "./modules/cosmos_db"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  suffix              = random_string.suffix.result
}

module "platform" {
  source              = "./modules/platform"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  suffix              = random_string.suffix.result
  storage = {
    id = module.storage.storage_account_id
    name = module.storage.storage_account_name
    container_name = module.storage.storage_container_name
    checkpoint_container_name = module.storage.storage_container_checkpoint_name
  }
  eventhub = {
    namespace_id = module.event_hub.namespace_id
    namespace_name = module.event_hub.namespace
    name = module.event_hub.name
  }
  cosmosdb = {
    id = module.cosmos_db.account_id
    name = module.cosmos_db.account_name
    endpoint = module.cosmos_db.account_endpoint
    database_name = module.cosmos_db.database_name
  }
}