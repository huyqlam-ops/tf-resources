output "acr_login_server" {
  description = "Login server của Azure Container Registry"
  value       = azurerm_container_registry.acr.login_server
}

output "container_app_environment_name" {
  description = "Tên Container Apps Environment"
  value       = azurerm_container_app_environment.cae.name
}

output "report_app_fqdn" {
  description = "FQDN public của Report Container App"
  value       = azurerm_container_app.report.latest_revision_fqdn
}

output "report_identity_client_id" {
  description = "Client ID của identity Report App (dùng cho GitHub Actions ACR login nếu cần)"
  value       = azurerm_user_assigned_identity.report_identity.client_id
}

output "ingest_identity_client_id" {
  description = "Client ID của identity Ingest App"
  value       = azurerm_user_assigned_identity.ingest_identity.client_id
}

output "storage_account_name" {
  description = "Tên của Storage Account"
  value       = azurerm_storage_account.storage.name
}

output "storage_container_name" {
  description = "Tên container blob chính"
  value       = azurerm_storage_container.container.name
}

output "storage_container_checkpoint_name" {
  description = "Tên container checkpoint cho Event Processor"
  value       = azurerm_storage_container.checkpoint.name
}

output "eventhubs_namespace" {
  description = "Tên Event Hubs Namespace"
  value       = azurerm_eventhub_namespace.ehns.name
}

output "eventhubs_name" {
  description = "Tên Event Hub"
  value       = azurerm_eventhub.eh.name
}

output "cosmosdb_endpoint" {
  description = "Endpoint của Cosmos DB Account"
  value       = azurerm_cosmosdb_account.cosmos.endpoint
}

output "cosmosdb_database_name" {
  description = "Tên Cosmos DB Database"
  value       = azurerm_cosmosdb_sql_database.db.name
}

output "ingest_app_fqdn" {
  description = "FQDN của Ingest Container App (nếu có bật ingress external)"
  value       = azurerm_container_app.ingest.name   # hoặc .latest_revision_fqdn nếu ingress external = true
}

output "container_app_resource_group" {
  value = azurerm_resource_group.rg.name
}

output "acr_name" {
  value = azurerm_container_registry.acr.name   # tên gốc, không kèm .azurecr.io
}