# Lấy Client ID / Identity đang thực thi Terraform
data "azurerm_client_config" "current" {}

# 1. Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "rg-training-microservices"
  location = "East Asia"
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# 2. Azure Storage Account
resource "azurerm_storage_account" "storage" {
  name                     = "streportapp${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
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

# Quyền đọc/ghi Blob (RBAC - passwordless)
resource "azurerm_role_assignment" "blob_contributor" {
  scope                = azurerm_storage_account.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# 3. Azure Event Hubs Namespace & Event Hub
resource "azurerm_eventhub_namespace" "ehns" {
  name                = "ehns-reportapp-${random_string.suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
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
  principal_id         = data.azurerm_client_config.current.object_id
}

# 4. Cosmos DB Account (NoSQL API) & Database
resource "azurerm_cosmosdb_account" "cosmos" {
  name                = "cosmos-reportapp-${random_string.suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.rg.location
    failover_priority = 0
  }
}

resource "azurerm_cosmosdb_sql_database" "db" {
  name                = "ReportDb"
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmos.name
}

resource "azurerm_cosmosdb_sql_container" "container" {
  name                = "reports"
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmos.name
  database_name       = azurerm_cosmosdb_sql_database.db.name
  partition_key_paths  = ["/key"]
}

# Quyền ghi Cosmos DB (built-in role 00000000-0000-0000-0000-000000000002 = Cosmos DB Built-in Data Contributor)
resource "azurerm_cosmosdb_sql_role_assignment" "cosmos_rbac" {
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmos.name
  role_definition_id  = "${azurerm_cosmosdb_account.cosmos.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = data.azurerm_client_config.current.object_id
  scope                = azurerm_cosmosdb_account.cosmos.id
}

# 5. Log Analytics Workspace (bắt buộc để tạo Container Apps Environment)
resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-reportapp-${random_string.suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# 6. Azure Container Registry
resource "azurerm_container_registry" "acr" {
  name                = "acrreportapp${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = false
}

# 7. Container Apps Environment
resource "azurerm_container_app_environment" "cae" {
  name                       = "cae-reportapp-${random_string.suffix.result}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
}

# 8. User Assigned Identity riêng cho từng Container App
# (tách riêng khỏi identity của Container App để tránh vòng lặp: role assignment <-> identity)
resource "azurerm_user_assigned_identity" "report_identity" {
  name                = "id-ca-report-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

resource "azurerm_user_assigned_identity" "ingest_identity" {
  name                = "id-ca-ingest-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

# Quyền pull image từ ACR cho từng identity
resource "azurerm_role_assignment" "report_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.report_identity.principal_id
}

resource "azurerm_role_assignment" "ingest_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.ingest_identity.principal_id
}

# 9. Container App - Report
resource "azurerm_container_app" "report" {
  name                         = "ca-report-${random_string.suffix.result}"
  container_app_environment_id = azurerm_container_app_environment.cae.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.report_identity.id]
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.report_identity.id
  }

  template {
    container {
      name   = "report"
      # Ảnh placeholder cho lần apply đầu tiên - CI/CD sẽ cập nhật ảnh thật sau khi build & push lên ACR
      image  = "mcr.microsoft.com/k8se/quickstart:latest"
      cpu    = 0.5
      memory = "1Gi"
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  # Không để terraform ghi đè lại ảnh mà pipeline CI/CD đã deploy
  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [azurerm_role_assignment.report_acr_pull]
}

# 10. Container App - Ingest
resource "azurerm_container_app" "ingest" {
  name                         = "ca-ingest-${random_string.suffix.result}"
  container_app_environment_id = azurerm_container_app_environment.cae.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.ingest_identity.id]
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.ingest_identity.id
  }

  template {
    container {
      name   = "ingest"
      image  = "mcr.microsoft.com/k8se/quickstart:latest"
      cpu    = 0.5
      memory = "1Gi"
    }
  }

  ingress {
    external_enabled = false # ingest nhận event nội bộ, không cần public ingress - đổi thành true nếu cần expose
    target_port       = 8080
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [azurerm_role_assignment.ingest_acr_pull]
}