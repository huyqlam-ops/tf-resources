output "namespace_id" {
  value = azurerm_eventhub_namespace.ehns.id
}

output "namespace" {
  value       = azurerm_eventhub_namespace.ehns.name
}

output "name" {
  value       = azurerm_eventhub.eh.name
}