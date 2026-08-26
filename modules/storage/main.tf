resource "azurerm_storage_account" "storage" {
  name                     = "streportapp${var.suffix}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "container" {
  name                  = "my-blob-container"
  storage_account_id    = azurerm_storage_account.storage.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "checkpoint" {
  name                  = "checkpoint"
  storage_account_id    = azurerm_storage_account.storage.id
  container_access_type = "private"
}

# resource "azurerm_role_assignment" "blob_contributor" {
#   scope                = azurerm_storage_account.storage.id
#   role_definition_name = "Storage Blob Data Contributor"
#   principal_id         = data.azurerm_client_config.current.object_id
# }