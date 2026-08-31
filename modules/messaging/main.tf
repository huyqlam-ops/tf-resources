# Event Hub
resource "azurerm_eventhub_namespace" "ehns" {
  name                = "ehns-reportapp-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Standard"
  capacity            = 1
}

resource "azurerm_eventhub" "eh" {
  name                = "evh-reports"
  namespace_id = azurerm_eventhub_namespace.ehns.id
  partition_count     = 2
  message_retention   = 1
}

# Service Bus
resource "azurerm_servicebus_namespace" "sbns" {
  name = "sbns-reportapp-${var.suffix}"
  location = var.location
  resource_group_name = var.resource_group_name
  sku = "Standard"
}

resource "azurerm_servicebus_queue" "batch_queue" {
  name = "q-batch-ingest"
  namespace_id = azurerm_servicebus_namespace.sbns.id
}

# Event Grid
resource "azurerm_eventgrid_system_topic" "storage_events" {
  name = "evgt-storage-${var.suffix}"
  location = var.location
  resource_group_name = var.resource_group_name
  source_resource_id = var.storage_account_id
  topic_type = "Microsoft.Storage.StorageAccounts"
}

resource "azurerm_eventgrid_system_topic_event_subscription" "blob_to_servicebus" {
  name = "evgs-batch-upload"
  system_topic = azurerm_eventgrid_system_topic.storage_events.name
  resource_group_name = var.resource_group_name

  service_bus_queue_endpoint_id = azurerm_servicebus_queue.batch_queue.id

  included_event_types = [
    "Microsoft.Storage.BlobCreated"
  ]

  subject_filter {
    subject_begins_with = var.event_grid_subcription_folder
  }
}

# Quyền đọc/ghi Event Hubs (RBAC - passwordless)
resource "azurerm_role_assignment" "eventhub_owner" {
  scope                = azurerm_eventhub_namespace.ehns.id
  role_definition_name = "Azure Event Hubs Data Owner"
  principal_id         = var.current_object_id
}