# Lấy Client ID / Identity đang thực thi Terraform
data "azurerm_client_config" "current" {}

locals {
    batch_raw_data_dir = "batch_raw_data"
    data_dir = "data"
}

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
  current_object_id = data.azurerm_client_config.current.object_id
}

module "messaging" {
  source              = "./modules/messaging"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  suffix              = random_string.suffix.result
  current_object_id = data.azurerm_client_config.current.object_id
  storage_account_id = module.storage.storage_account_id
  event_grid_subcription_folder = "/blobServices/default/containers/${module.storage.storage_container_name}/${local.batch_raw_data_dir}/"
}

module "cosmos_db" {
  source              = "./modules/cosmos_db"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  suffix              = random_string.suffix.result
  current_object_id = data.azurerm_client_config.current.object_id
}

module "platform" {
  source              = "./modules/platform"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  suffix              = random_string.suffix.result
  raw_data_dir = local.batch_raw_data_dir
  data_dir = local.data_dir
  servicebus_queue_name = module.messaging.servicebus_queue_name
  servicebus_namespace = module.messaging.servicebus_namespace
  servicebus_namespace_id = module.messaging.servicebus_namespace_id

  storage = {
    id = module.storage.storage_account_id
    name = module.storage.storage_account_name
    container_name = module.storage.storage_container_name
    checkpoint_container_name = module.storage.storage_container_checkpoint_name
  }
  eventhub = {
    namespace_id = module.messaging.eventhub_namespace_id
    namespace_name = module.messaging.eventhub_namespace
    name = module.messaging.eventhub_name
  }
  cosmosdb = {
    id = module.cosmos_db.account_id
    name = module.cosmos_db.account_name
    endpoint = module.cosmos_db.account_endpoint
    database_name = module.cosmos_db.database_name
  }
}