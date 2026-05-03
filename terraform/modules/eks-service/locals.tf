locals {
  # ── Environment-specific defaults ──────────────────────────────────
  env_defaults = {
    dev = {
      replicas = 1
      hpa_min  = 1
      hpa_max  = 3
    }
    staging = {
      replicas = 2
      hpa_min  = 2
      hpa_max  = 5
    }
    prod = {
      replicas = 3
      hpa_min  = 3
      hpa_max  = 10
    }
  }

  defaults = local.env_defaults[var.environment]

  # ── Effective values: explicit override > env default ──────────────
  effective_replicas  = coalesce(var.replicas, local.defaults.replicas)
  effective_hpa_min   = coalesce(var.hpa_min_replicas, local.defaults.hpa_min)
  effective_hpa_max   = coalesce(var.hpa_max_replicas, local.defaults.hpa_max)

  # ── Resolved namespace ─────────────────────────────────────────────
  namespace = var.create_namespace ? kubernetes_namespace_v1.this[0].metadata[0].name : var.namespace

  # ── Kubernetes labels ──────────────────────────────────────────────
  common_labels = merge(
    {
      "app.kubernetes.io/name"       = var.name
      "app.kubernetes.io/instance"   = "${var.name}-${var.environment}"
      "app.kubernetes.io/managed-by" = "terraform"
      "environment"                  = var.environment
    },
    var.labels,
  )

  # matchLabels must be a stable subset of template labels
  selector_labels = {
    "app.kubernetes.io/name"     = var.name
    "app.kubernetes.io/instance" = "${var.name}-${var.environment}"
  }

  # ── Pod annotations (with optional Prometheus scrape config) ────────
  pod_annotations = merge(
    var.pod_annotations,
    var.enable_prometheus ? {
      "prometheus.io/scrape" = "true"
      "prometheus.io/port"   = tostring(coalesce(var.prometheus_port, var.container_port))
      "prometheus.io/path"   = var.prometheus_path
    } : {},
  )
}
