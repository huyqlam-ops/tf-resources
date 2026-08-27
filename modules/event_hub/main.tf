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

# Quyền đọc/ghi Event Hubs (RBAC - passwordless)
resource "azurerm_role_assignment" "eventhub_owner" {
  scope                = azurerm_eventhub_namespace.ehns.id
  role_definition_name = "Azure Event Hubs Data Owner"
  principal_id         = var.current_object_id
}