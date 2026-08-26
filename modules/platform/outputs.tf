output "acr_login_server" {
  value       = azurerm_container_registry.acr.login_server
}

output "acr_name" {
  value = azurerm_container_registry.acr.name
}

output "container_app_environment_name" {
  value       = azurerm_container_app_environment.cae.name
}

output "report_identity_client_id" {
  value       = azurerm_user_assigned_identity.report_identity.client_id
}

output "ingest_identity_client_id" {
  value       = azurerm_user_assigned_identity.ingest_identity.client_id
}

output "report_app_name" {
  value       = azurerm_container_app.report.name
}

output "ingest_app_name" {
  value       = azurerm_container_app.ingest.name
}

output "report_app_fqdn" {
  value       = azurerm_container_app.report.latest_revision_fqdn
}

output "prometheus_internal_fqdn" {
  value = azurerm_container_app.prometheus.ingress[0].fqdn
}

output "loki_internal_fqdn" {
  value = azurerm_container_app.loki.ingress[0].fqdn
}

output "prometheus_url" {
  value = "https://${azurerm_container_app.prometheus.ingress[0].fqdn}"
}

output "loki_url" {
  value = "https://${azurerm_container_app.loki.ingress[0].fqdn}"
}

output "grafana_url" {
  value = "https://${azurerm_container_app.grafana.ingress[0].fqdn}"
}
