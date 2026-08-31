output "eventhub_namespace_id" {
  value = azurerm_eventhub_namespace.ehns.id
}

output "eventhub_namespace" {
  value       = azurerm_eventhub_namespace.ehns.name
}

output "eventhub_name" {
  value       = azurerm_eventhub.eh.name
}

output "servicebus_queue_name" {
  value       = azurerm_servicebus_queue.batch_queue.name
}

output "servicebus_namespace" {
  value       = azurerm_servicebus_namespace.sbns.name
}
output "servicebus_namespace_id" {
  value       = azurerm_servicebus_namespace.sbns.id
}