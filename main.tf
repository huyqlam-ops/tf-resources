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

# ---- Event Hubs: report chỉ gửi (least privilege - không cần Owner) ----
resource "azurerm_role_assignment" "report_eventhub_sender" {
  scope                = azurerm_eventhub_namespace.ehns.id
  role_definition_name = "Azure Event Hubs Data Sender"
  principal_id         = azurerm_user_assigned_identity.report_identity.principal_id
}

# ---- Event Hubs: ingest chỉ nhận ----
resource "azurerm_role_assignment" "ingest_eventhub_receiver" {
  scope                = azurerm_eventhub_namespace.ehns.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = azurerm_user_assigned_identity.ingest_identity.principal_id
}

# ---- Blob Storage: chỉ ingest cần, vì Spring Cloud Azure EventProcessor
#      dùng blob container "checkpoint" để lưu vị trí đã đọc tới đâu ----
resource "azurerm_role_assignment" "ingest_blob_contributor" {
  scope                = azurerm_storage_account.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.ingest_identity.principal_id
}

resource "azurerm_role_assignment" "report_blob_contributor" {
  scope                = azurerm_storage_account.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.report_identity.principal_id
}

# ---- Cosmos DB: chỉ ingest ghi dữ liệu report đã xử lý ----
resource "azurerm_cosmosdb_sql_role_assignment" "ingest_cosmos_rbac" {
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmos.name
  role_definition_id  = "${azurerm_cosmosdb_account.cosmos.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002" # Data Contributor
  principal_id        = azurerm_user_assigned_identity.ingest_identity.principal_id
  scope                = azurerm_cosmosdb_account.cosmos.id
}

# ---- Cosmos DB: report chỉ ĐỌC để trả dữ liệu qua API (bỏ nếu report không đọc trực tiếp Cosmos) ----
resource "azurerm_cosmosdb_sql_role_assignment" "report_cosmos_reader" {
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmos.name
  role_definition_id  = "${azurerm_cosmosdb_account.cosmos.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000001" # Data Reader (built-in, chỉ đọc)
  principal_id        = azurerm_user_assigned_identity.report_identity.principal_id
  scope                = azurerm_cosmosdb_account.cosmos.id
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
    min_replicas = 0
    max_replicas = 1

    volume {
      name = "shared-logs"
    }

    container {
      name   = "report"
      # Ảnh placeholder cho lần apply đầu tiên - CI/CD sẽ cập nhật ảnh thật sau khi build & push lên ACR
      image  = "mcr.microsoft.com/k8se/quickstart:latest"
      cpu    = 0.5
      memory = "1Gi"

      volume_mounts {
        name = "shared-logs"
        path = "/var/log/app"
      }
      
      env {
        name  = "AZURE_EVENTHUBS_NAMESPACE"
        value = azurerm_eventhub_namespace.ehns.name
      }
      env {
        name  = "AZURE_EVENTHUBS_NAME"
        value = azurerm_eventhub.eh.name
      }
      env {
        name  = "AZURE_STORAGE_ACCOUNT"
        value = azurerm_storage_account.storage.name
      }
      env {
        name  = "STORAGE_CONTAINER_NAME"
        value = azurerm_storage_container.container.name
      }
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.report_identity.client_id
      }

      env {
        name = "LOG_FILE_PATH" 
        value = "/var/log/app/app.log"
      }
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
    min_replicas = 1
    max_replicas = 2

    volume {
      name = "shared-logs"
    }

    container {
      name   = "ingest"
      image  = "mcr.microsoft.com/k8se/quickstart:latest"
      cpu    = 0.5
      memory = "1Gi"

      volume_mounts {
        name = "shared-logs"
        path = "/var/log/app"
      }

      env {
        name  = "AZURE_STORAGE_ACCOUNT"
        value = azurerm_storage_account.storage.name
      }
      env {
        name  = "STORAGE_CONTAINER_NAME"
        value = azurerm_storage_container.container.name
      }
      env {
        name  = "STORAGE_CONTAINER_CHECKPOINT"
        value = azurerm_storage_container.checkpoint.name
      }
      env {
        name  = "AZURE_EVENTHUBS_NAMESPACE"
        value = azurerm_eventhub_namespace.ehns.name
      }
      env {
        name  = "AZURE_EVENTHUBS_NAME"
        value = azurerm_eventhub.eh.name
      }
      env {
        name  = "AZURE_COSMOS_ENDPOINT"
        value = azurerm_cosmosdb_account.cosmos.endpoint
      }
      env {
        name  = "AZURE_COSMOS_DATABASE"
        value = azurerm_cosmosdb_sql_database.db.name
      }
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.ingest_identity.client_id
      }

      env {
        name = "LOG_FILE_PATH" 
        value = "/var/log/app/app.log"
      }
    }

    container {
      name   = "alloy"
      image  = "grafana/alloy:latest"
      cpu    = 0.25
      memory = "0.5Gi"

      volume_mounts {
        name = "shared-logs"
        path = "/var/log/app"
      }

      command = ["/bin/sh", "-c"]
      args = [
        <<-EOT
        cat <<'EOF' > /etc/alloy/config.alloy
        prometheus.scrape "app" {
          targets = [{"__address__" = "localhost:8080"}]
          metrics_path = "/actuator/prometheus"
          forward_to = [prometheus.remote_write.default.receiver]
        }

        prometheus.remote_write "default" {
          endpoint {
            url = "http://${azurerm_container_app.prometheus.ingress[0].fqdn}/api/v1/write"
          }
        }

        loki.source.file "app_logs" {
          targets = [{
            __path__ = "/var/log/app/app.log"
            app      = "ingest"
          }]
          forward_to = [loki.write.default.receiver]
        }

        loki.write "default" {
          endpoint {
            url = "http://${azurerm_container_app.loki.ingress[0].fqdn}/loki/api/v1/push"
          }
        }
        EOF
        exec /bin/alloy run /etc/alloy/config.alloy --server.http.listen-addr=0.0.0.0:12345 --stability.level=experimental
        EOT
      ]
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

  depends_on = [
    azurerm_role_assignment.ingest_acr_pull,
    azurerm_container_app.prometheus,
    azurerm_container_app.loki,
  ]
}