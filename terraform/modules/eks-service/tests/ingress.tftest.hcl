mock_provider "kubernetes" {}

variables {
  name        = "ingress-svc"
  namespace   = "ingress-ns"
  environment = "staging"
  image       = "nginx"
  image_tag   = "1.27"

  resources = {
    requests = { cpu = "100m", memory = "128Mi" }
    limits   = { cpu = "200m", memory = "256Mi" }
  }
}

# ─────────────────────────────────────────────────────────────────────
# Ingress disabled by default
# ─────────────────────────────────────────────────────────────────────

run "ingress_disabled_by_default" {
  command = plan

  assert {
    condition     = length(kubernetes_ingress_v1.this) == 0
    error_message = "Ingress should not be created by default"
  }

  assert {
    condition     = output.ingress_hostname == ""
    error_message = "ingress_hostname output should be empty when disabled"
  }
}

# ─────────────────────────────────────────────────────────────────────
# Ingress with TLS
# ─────────────────────────────────────────────────────────────────────

run "ingress_with_tls" {
  command = plan

  variables {
    enable_ingress     = true
    ingress_host       = "api.example.com"
    ingress_tls_secret = "api-tls"
    ingress_class      = "nginx"
  }

  assert {
    condition     = length(kubernetes_ingress_v1.this) == 1
    error_message = "Ingress should be created when enabled"
  }

  assert {
    condition     = output.ingress_hostname == "api.example.com"
    error_message = "ingress_hostname output should match var.ingress_host"
  }
}

# ─────────────────────────────────────────────────────────────────────
# Prometheus annotations injected when enabled
# ─────────────────────────────────────────────────────────────────────

run "prometheus_annotations" {
  command = plan

  variables {
    enable_prometheus = true
    prometheus_path   = "/metrics"
  }

  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].metadata[0].annotations["prometheus.io/scrape"] == "true"
    error_message = "Pod should have prometheus.io/scrape annotation"
  }

  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].metadata[0].annotations["prometheus.io/path"] == "/metrics"
    error_message = "Pod should have prometheus.io/path annotation"
  }
}

# ─────────────────────────────────────────────────────────────────────
# External secret bypasses module-managed secret
# ─────────────────────────────────────────────────────────────────────

run "external_secret_used" {
  command = plan

  variables {
    external_secret_name = "my-eso-secret"
    secret_data = {
      SHOULD_NOT_CREATE = "true"
    }
  }

  assert {
    condition     = length(kubernetes_secret_v1.this) == 0
    error_message = "Module-managed Secret should not be created when external_secret_name is set, even if secret_data is provided"
  }

  assert {
    condition     = length(kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].env_from) == 1
    error_message = "Deployment should have one secret envFrom source when external_secret_name is provided"
  }

  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].env_from[0].secret_ref[0].name == "my-eso-secret"
    error_message = "Deployment should reference external_secret_name in envFrom"
  }
}

run "no_secret_env_from_when_no_secret_sources" {
  command = plan

  variables {
    external_secret_name = null
    secret_data          = {}
  }

  assert {
    condition     = length(kubernetes_secret_v1.this) == 0
    error_message = "No module-managed Secret should be created when secret_data is empty and external_secret_name is null"
  }

  assert {
    condition     = length(kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].env_from) == 0
    error_message = "Deployment should not include secret envFrom when no secret source exists"
  }
}
