output "account_id" {
  value = azurerm_cosmosdb_account.cosmos.id
}

output "account_name" {
  value = azurerm_cosmosdb_account.cosmos.name
}

output "account_endpoint" {
  value       = azurerm_cosmosdb_account.cosmos.endpoint
}

output "database_name" {
  value       = azurerm_cosmosdb_sql_database.db.name
}