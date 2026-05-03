resource "kubernetes_horizontal_pod_autoscaler_v2" "this" {
  count = var.enable_hpa ? 1 : 0

  metadata {
    name      = var.name
    namespace = local.namespace
    labels    = local.common_labels
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment_v1.this.metadata[0].name
    }

    min_replicas = local.effective_hpa_min
    max_replicas = local.effective_hpa_max

    # CPU metric (always present when HPA is enabled)
    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.hpa_cpu_target
        }
      }
    }

    # Memory metric (opt-in)
    dynamic "metric" {
      for_each = var.hpa_memory_target != null ? [var.hpa_memory_target] : []
      content {
        type = "Resource"
        resource {
          name = "memory"
          target {
            type                = "Utilization"
            average_utilization = metric.value
          }
        }
      }
    }

    # ── Scaling behavior (prevents thrashing) ──────────────────
    behavior {
      scale_up {
        stabilization_window_seconds = var.hpa_scale_up_stabilization
        select_policy                = "Max"

        policy {
          type           = "Percent"
          value          = 100
          period_seconds = 60
        }
      }

      scale_down {
        stabilization_window_seconds = var.hpa_scale_down_stabilization
        select_policy                = "Max"

        policy {
          type           = "Percent"
          value          = 25
          period_seconds = 60
        }
      }
    }
  }
}
