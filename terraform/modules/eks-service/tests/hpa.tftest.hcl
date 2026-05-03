mock_provider "kubernetes" {}

variables {
  name        = "hpa-svc"
  namespace   = "hpa-ns"
  environment = "prod"
  image       = "nginx"
  image_tag   = "1.27"

  resources = {
    requests = { cpu = "250m", memory = "256Mi" }
    limits   = { cpu = "500m", memory = "512Mi" }
  }

  readiness_probe = { path = "/healthz" }
  liveness_probe  = { path = "/healthz" }

  enable_hpa = true
}

# ─────────────────────────────────────────────────────────────────────
# HPA picks up prod environment defaults
# ─────────────────────────────────────────────────────────────────────

run "hpa_uses_prod_defaults" {
  command = plan

  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this[0].spec[0].min_replicas == 3
    error_message = "HPA min_replicas should default to 3 for prod"
  }

  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this[0].spec[0].max_replicas == 10
    error_message = "HPA max_replicas should default to 10 for prod"
  }
}

# ─────────────────────────────────────────────────────────────────────
# Explicit overrides beat env defaults
# ─────────────────────────────────────────────────────────────────────

run "hpa_overrides_env_defaults" {
  command = plan

  variables {
    hpa_min_replicas = 5
    hpa_max_replicas = 20
  }

  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this[0].spec[0].min_replicas == 5
    error_message = "Explicit hpa_min_replicas should override env default"
  }

  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this[0].spec[0].max_replicas == 20
    error_message = "Explicit hpa_max_replicas should override env default"
  }
}

# ─────────────────────────────────────────────────────────────────────
# HPA disabled → no resource created
# ─────────────────────────────────────────────────────────────────────

run "hpa_disabled" {
  command = plan

  variables {
    enable_hpa = false
  }

  assert {
    condition     = length(kubernetes_horizontal_pod_autoscaler_v2.this) == 0
    error_message = "No HPA should exist when enable_hpa = false"
  }
}
