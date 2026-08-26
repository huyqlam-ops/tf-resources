output "container_app_resource_group" {
  value = azurerm_resource_group.rg.name
}
output "acr_login_server" {
  value       = module.platform.acr_login_server
}
output "acr_name" {
  value       = module.platform.acr_name
}
output "report_app_name" {
  value       = module.platform.report_app_name
}
output "ingest_app_name" {
  value       = module.platform.ingest_app_name
}
output "report_app_fqdn" {
  value       = module.platform.report_app_fqdn
}
output "grafana_url" {
  value = module.platform.grafana_url
}
