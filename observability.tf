# ==== Observability Stack: Prometheus + Loki + Grafana (self-hosted, ephemeral storage) ====

resource "random_password" "grafana_admin" {
  length  = 20
  special = true
}

# ---------- Prometheus ----------
resource "azurerm_container_app" "prometheus" {
  name                         = "ca-prometheus-${random_string.suffix.result}"
  container_app_environment_id = azurerm_container_app_environment.cae.id
  resource_group_name          = azurerm_resource_group.rg.name
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
  name                         = "ca-loki-${random_string.suffix.result}"
  container_app_environment_id = azurerm_container_app_environment.cae.id
  resource_group_name          = azurerm_resource_group.rg.name
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
  name                         = "ca-grafana-${random_string.suffix.result}"
  container_app_environment_id = azurerm_container_app_environment.cae.id
  resource_group_name          = azurerm_resource_group.rg.name
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

# ==== Outputs ====
output "prometheus_internal_fqdn" {
  value = azurerm_container_app.prometheus.ingress[0].fqdn
}

output "loki_internal_fqdn" {
  value = azurerm_container_app.loki.ingress[0].fqdn
}

output "grafana_url" {
  value = "https://${azurerm_container_app.grafana.ingress[0].fqdn}"
}

output "grafana_admin_password" {
  value     = random_password.grafana_admin.result
  sensitive = true
}