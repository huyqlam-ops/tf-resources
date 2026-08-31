locals {
  log_file_path = "/var/log/app/app.log"
}

# 5. Log Analytics Workspace (bắt buộc để tạo Container Apps Environment)
resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-reportapp-${var.suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# 6. Azure Container Registry
resource "azurerm_container_registry" "acr" {
  name                = "acrreportapp${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = false
}

# 7. Container Apps Environment
resource "azurerm_container_app_environment" "cae" {
  name                       = "cae-reportapp-${var.suffix}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
}

# 8. User Assigned Identity riêng cho từng Container App
# (tách riêng khỏi identity của Container App để tránh vòng lặp: role assignment <-> identity)
resource "azurerm_user_assigned_identity" "report_identity" {
  name                = "id-ca-report-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_user_assigned_identity" "ingest_identity" {
  name                = "id-ca-ingest-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_user_assigned_identity" "batchingest_identity" {
  name                = "id-ca-batchingest-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
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

resource "azurerm_role_assignment" "batchingest_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.batchingest_identity.principal_id
}

# ---- Event Hubs: report chỉ gửi (least privilege - không cần Owner) ----
resource "azurerm_role_assignment" "report_eventhub_sender" {
  scope                = var.eventhub.namespace_id
  role_definition_name = "Azure Event Hubs Data Sender"
  principal_id         = azurerm_user_assigned_identity.report_identity.principal_id
}

resource "azurerm_role_assignment" "ingest_eventhub_receiver" {
  scope                = var.eventhub.namespace_id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = azurerm_user_assigned_identity.ingest_identity.principal_id
}

# ---- Blob Storage ----
resource "azurerm_role_assignment" "ingest_blob_contributor" {
  scope                = var.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.ingest_identity.principal_id
}

resource "azurerm_role_assignment" "report_blob_contributor" {
  scope                = var.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.report_identity.principal_id
}

resource "azurerm_role_assignment" "batchingest_blob_contributor" {
  scope                = var.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.batchingest_identity.principal_id
}

# ---- Cosmos DB ----
resource "azurerm_cosmosdb_sql_role_assignment" "ingest_cosmos_rbac" {
  resource_group_name = var.resource_group_name
  account_name        = var.cosmosdb.name
  role_definition_id  = "${var.cosmosdb.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002" # Data Contributor
  principal_id        = azurerm_user_assigned_identity.ingest_identity.principal_id
  scope                = var.cosmosdb.id
}

resource "azurerm_cosmosdb_sql_role_assignment" "report_cosmos_reader" {
  resource_group_name = var.resource_group_name
  account_name        = var.cosmosdb.name
  role_definition_id  = "${var.cosmosdb.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000001" # Data Reader (built-in, chỉ đọc)
  principal_id        = azurerm_user_assigned_identity.report_identity.principal_id
  scope                = var.cosmosdb.id
}

resource "azurerm_cosmosdb_sql_role_assignment" "batchingest_cosmos_rbac" {
  resource_group_name = var.resource_group_name
  account_name        = var.cosmosdb.name
  role_definition_id  = "${var.cosmosdb.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id         = azurerm_user_assigned_identity.batchingest_identity.principal_id
  scope                = var.cosmosdb.id
}

# ---- Service Bus DB ----
resource "azurerm_role_assignment" "batchingest_servicebus_receiver" {
  scope                = var.servicebus_namespace_id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_user_assigned_identity.batchingest_identity.principal_id
}

resource "random_password" "grafana_admin" {
  length  = 20
  special = true
}

# ---------- Prometheus ----------
resource "azurerm_container_app" "prometheus" {
  name                         = "ca-prometheus-${var.suffix}"
  container_app_environment_id = azurerm_container_app_environment.cae.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  template {
    min_replicas = 1
    max_replicas = 1
    
    container {
      name   = "prometheus"
      image  = "prom/prometheus:latest"
      cpu    = 0.5
      memory = "1Gi"

      args = [
        "--config.file=/etc/prometheus/prometheus.yml",
        "--storage.tsdb.path=/prometheus",
        "--web.enable-remote-write-receiver",
      ]
    }
  }

  ingress {
    external_enabled = false
    target_port       = 9090
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}

# ---------- Loki ----------
resource "azurerm_container_app" "loki" {
  name                         = "ca-loki-${var.suffix}"
  container_app_environment_id = azurerm_container_app_environment.cae.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "loki"
      image  = "grafana/loki:latest"
      cpu    = 0.5
      memory = "1Gi"

      args = ["-config.file=/etc/loki/local-config.yaml"]
    }
  }

  ingress {
    external_enabled = false
    target_port       = 3100
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}

# ---------- Grafana ----------
resource "azurerm_container_app" "grafana" {
  name                         = "ca-grafana-${var.suffix}"
  container_app_environment_id = azurerm_container_app_environment.cae.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  secret {
    name  = "grafana-admin-password"
    value = random_password.grafana_admin.result
  }

  template {
    min_replicas = 1
    max_replicas = 1
    container {
      name   = "grafana"
      image  = "grafana/grafana:latest"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "GF_SECURITY_ADMIN_USER"
        value = "admin"
      }
      env {
        name        = "GF_SECURITY_ADMIN_PASSWORD"
        secret_name = "grafana-admin-password"
      }
      env {
        name  = "GF_INSTALL_PLUGINS"
        value = ""
      }
    }
  }

  ingress {
    external_enabled = true
    target_port       = 3000
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}

resource "random_password" "report_admin" {
  length  = 20
  special = true
}

# 9. Container App - Report
resource "azurerm_container_app" "report" {
  name                         = "ca-report-${var.suffix}"
  container_app_environment_id = azurerm_container_app_environment.cae.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.report_identity.id]
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.report_identity.id
  }

  secret {
    name = "report-admin-password" 
    value = random_password.report_admin.result
  }

  template {
    min_replicas = 0
    max_replicas = 1

    volume {
      name = "shared-logs"
    }

    container {
      name   = "report"
      image  = "mcr.microsoft.com/k8se/quickstart:latest"
      cpu    = 0.5
      memory = "1Gi"

      volume_mounts {
        name = "shared-logs"
        path = "/var/log/app"
      }
      
      env {
        name  = "AZURE_EVENTHUBS_NAMESPACE"
        value = var.eventhub.namespace_name
      }
      env {
        name  = "AZURE_EVENTHUBS_NAME"
        value = var.eventhub.name
      }
      env {
        name  = "AZURE_STORAGE_ACCOUNT"
        value = var.storage.name
      }
      env {
        name  = "STORAGE_CONTAINER_NAME"
        value = var.storage.container_name
      }
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.report_identity.client_id
      }
      env {
        name = "LOG_FILE_PATH" 
        value = local.log_file_path
      }
      env {
        name = "ADMIN_USER_PASSWORD" 
        secret_name = "report-admin-password"  
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
        echo '${base64encode(<<-CONFIG
          prometheus.scrape "app" {
            targets = [{"__address__" = "localhost:8080"}]
            metrics_path = "/actuator/prometheus"
            scrape_interval = "15s"
            forward_to = [prometheus.remote_write.default.receiver]
          }

          prometheus.remote_write "default" {
            endpoint {
              url = "https://${azurerm_container_app.prometheus.ingress[0].fqdn}/api/v1/write"
            }
          }

          loki.source.file "app_logs" {
            targets = [{
              __path__ = "/var/log/app/*.log",
              app      = "report",
            }]
            forward_to    = [loki.write.default.receiver]
            tail_from_end = false

            file_match {
              enabled     = true
              sync_period = "5s"
            }
          }

          loki.write "default" {
            endpoint {
              url = "https://${azurerm_container_app.loki.ingress[0].fqdn}/loki/api/v1/push"
            }
          }
        CONFIG
        )}' | base64 -d > /etc/alloy/config.alloy
        exec /bin/alloy run /etc/alloy/config.alloy --server.http.listen-addr=0.0.0.0:12345
        EOT
      ]
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

  depends_on = [
    azurerm_role_assignment.report_acr_pull,
    azurerm_container_app.prometheus,
    azurerm_container_app.loki,
  ]
}

# 10. Container App - Ingest
resource "azurerm_container_app" "ingest" {
  name                         = "ca-ingest-${var.suffix}"
  container_app_environment_id = azurerm_container_app_environment.cae.id
  resource_group_name          = var.resource_group_name
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
    min_replicas = 0
    max_replicas = 1

    volume {
      name = "shared-logs"
    }

    custom_scale_rule {
        name = "ingest-ca-eventhub-scale-rule"
        custom_rule_type = "azure-eventhub"
        metadata = { 
            eventHubNamespace = var.eventhub.namespace_name
            eventHubName      = var.eventhub.name
            consumerGroup     = "$Default"

            blobContainer      = var.storage.checkpoint_container_name
            checkpointStrategy = "blobMetadata"
            storageAccountName = var.storage.name

            activationUnprocessedEventThreshold = "1"
            unprocessedEventThreshold           = "64"
        }
        identity_id = azurerm_user_assigned_identity.ingest_identity.id
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
        value = var.storage.name
      }
      env {
        name  = "STORAGE_CONTAINER_NAME"
        value = var.storage.container_name
      }
      env {
        name  = "STORAGE_CONTAINER_CHECKPOINT"
        value = var.storage.checkpoint_container_name
      }
      env {
        name  = "AZURE_EVENTHUBS_NAMESPACE"
        value = var.eventhub.namespace_name
      }
      env {
        name  = "AZURE_EVENTHUBS_NAME"
        value = var.eventhub.name
      }
      env {
        name  = "AZURE_COSMOS_ENDPOINT"
        value = var.cosmosdb.endpoint
      }
      env {
        name  = "AZURE_COSMOS_DATABASE"
        value = var.cosmosdb.database_name
      }
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.ingest_identity.client_id
      }
      env {
        name = "LOG_FILE_PATH" 
        value = local.log_file_path
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
        echo '${base64encode(<<-CONFIG
          prometheus.scrape "app" {
            targets = [{"__address__" = "localhost:8080"}]
            metrics_path = "/actuator/prometheus"
            scrape_interval = "15s"
            forward_to = [prometheus.remote_write.default.receiver]
          }

          prometheus.remote_write "default" {
            endpoint {
              url = "https://${azurerm_container_app.prometheus.ingress[0].fqdn}/api/v1/write"
            }
          }

          loki.source.file "app_logs" {
            targets = [{
              __path__ = "/var/log/app/*.log",
              app      = "ingest",
            }]
            forward_to    = [loki.write.default.receiver]
            tail_from_end = false

            file_match {
              enabled     = true
              sync_period = "5s"
            }
          }

          loki.write "default" {
            endpoint {
              url = "https://${azurerm_container_app.loki.ingress[0].fqdn}/loki/api/v1/push"
            }
          }
        CONFIG
        )}' | base64 -d > /etc/alloy/config.alloy
        exec /bin/alloy run /etc/alloy/config.alloy --server.http.listen-addr=0.0.0.0:12345
        EOT
      ]
    }
  }

  ingress {
    external_enabled = false
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

resource "azurerm_container_app" "batchingest" {
  name                         = "ca-batchingest-${var.suffix}"
  container_app_environment_id = azurerm_container_app_environment.cae.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.batchingest_identity.id]
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.ingest_identity.id
  }

  template {
    min_replicas = 0
    max_replicas = 1

    volume {
      name = "shared-logs"
    }

    custom_scale_rule {
        name = "batchingest-ca-eventhub-scale-rule"
        custom_rule_type = "azure-servicebus"
        metadata = { 
            queueName = var.servicebus_queue_name
            namespace = var.servicebus_namespace
            activationMessageCount = "1"
            messageCount = "5"
        }
        identity_id = azurerm_user_assigned_identity.batchingest_identity.id
    }

    container {
      name   = "batchingest"
      image  = "mcr.microsoft.com/k8se/quickstart:latest"
      cpu    = 0.5
      memory = "1Gi"

      volume_mounts {
        name = "shared-logs"
        path = "/var/log/app"
      }

      env {
        name  = "AZURE_STORAGE_ACCOUNT"
        value = var.storage.name
      }
      env {
        name  = "STORAGE_CONTAINER_NAME"
        value = var.storage.container_name
      }
      env {
        name  = "AZURE_COSMOS_ENDPOINT"
        value = var.cosmosdb.endpoint
      }
      env {
        name  = "AZURE_COSMOS_DATABASE"
        value = var.cosmosdb.database_name
      }
      env {
        name  = "AZURE_SERVICEBUS_NAMESPACE"
        value = var.servicebus_namespace
      }
      env {
        name  = "AZURE_SERVICEBUS_QUEUE_NAME"
        value = var.servicebus_queue_name
      }
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.ingest_identity.client_id
      }
      env {
        name = "LOG_FILE_PATH" 
        value = local.log_file_path
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
        echo '${base64encode(<<-CONFIG
          prometheus.scrape "app" {
            targets = [{"__address__" = "localhost:8080"}]
            metrics_path = "/actuator/prometheus"
            scrape_interval = "15s"
            forward_to = [prometheus.remote_write.default.receiver]
          }

          prometheus.remote_write "default" {
            endpoint {
              url = "https://${azurerm_container_app.prometheus.ingress[0].fqdn}/api/v1/write"
            }
          }

          loki.source.file "app_logs" {
            targets = [{
              __path__ = "/var/log/app/*.log",
              app      = "batchingest",
            }]
            forward_to    = [loki.write.default.receiver]
            tail_from_end = false

            file_match {
              enabled     = true
              sync_period = "5s"
            }
          }

          loki.write "default" {
            endpoint {
              url = "https://${azurerm_container_app.loki.ingress[0].fqdn}/loki/api/v1/push"
            }
          }
        CONFIG
        )}' | base64 -d > /etc/alloy/config.alloy
        exec /bin/alloy run /etc/alloy/config.alloy --server.http.listen-addr=0.0.0.0:12345
        EOT
      ]
    }
  }

  ingress {
    external_enabled = false
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
    azurerm_role_assignment.batchingest_acr_pull,
    azurerm_container_app.prometheus,
    azurerm_container_app.loki,
  ]
}