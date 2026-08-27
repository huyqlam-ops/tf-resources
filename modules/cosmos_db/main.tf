# 4. Cosmos DB Account (NoSQL API) & Database
resource "azurerm_cosmosdb_account" "cosmos" {
  name                = "cosmos-reportapp-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }
}

resource "azurerm_cosmosdb_sql_database" "db" {
  name                = "ReportDb"
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.cosmos.name
}

resource "azurerm_cosmosdb_sql_container" "container" {
  name                = "reports"
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.cosmos.name
  database_name       = azurerm_cosmosdb_sql_database.db.name
  partition_key_paths  = ["/key"]
}

# Quyền ghi Cosmos DB (built-in role 00000000-0000-0000-0000-000000000002 = Cosmos DB Built-in Data Contributor)
resource "azurerm_cosmosdb_sql_role_assignment" "cosmos_rbac" {
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.cosmos.name
  role_definition_id  = "${azurerm_cosmosdb_account.cosmos.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = data.azurerm_client_config.current.object_id
  scope                = azurerm_cosmosdb_account.cosmos.id
}