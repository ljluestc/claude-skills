# ─────────────────────────────────────────────────────────────────────
# Deployment
# ─────────────────────────────────────────────────────────────────────

resource "kubernetes_deployment_v1" "this" {
  metadata {
    name      = var.name
    namespace = local.namespace
    labels    = local.common_labels
  }

  spec {
    # When HPA is active it owns replica count; null tells the provider
    # to omit the field so Kubernetes keeps the HPA-managed value.
    replicas = var.enable_hpa ? null : local.effective_replicas

    selector {
      match_labels = local.selector_labels
    }

    # ── Rollout strategy (zero-downtime by default) ────────────
    strategy {
      type = var.rollout_strategy.type

      rolling_update {
        max_surge       = var.rollout_strategy.max_surge
        max_unavailable = var.rollout_strategy.max_unavailable
      }
    }

    template {
      metadata {
        labels      = local.common_labels
        annotations = local.pod_annotations
      }

      spec {
        # ── Pod-level hardening ──────────────────────────────────
        security_context {
          run_as_non_root = var.security_context.run_as_non_root
          run_as_user     = var.security_context.run_as_user
          run_as_group    = var.security_context.run_as_group
          fs_group        = var.security_context.fs_group
        }

        service_account_name = var.enable_irsa ? kubernetes_service_account_v1.this[0].metadata[0].name : null

        container {
          name    = var.name
          image   = "${var.image}:${var.image_tag}"
          command = var.command
          args    = var.args

          # ── Container-level hardening ────────────────────────────
          security_context {
            allow_privilege_escalation = var.container_security_context.allow_privilege_escalation
            read_only_root_filesystem  = var.container_security_context.read_only_root_filesystem
            run_as_non_root            = var.container_security_context.run_as_non_root
          }

          port {
            container_port = var.container_port
            protocol       = "TCP"
          }

          # ── Resource requests / limits ───────────────────────────
          resources {
            requests = {
              cpu    = var.resources.requests.cpu
              memory = var.resources.requests.memory
            }
            limits = {
              cpu    = var.resources.limits.cpu
              memory = var.resources.limits.memory
            }
          }

          # ── Direct env vars ──────────────────────────────────────
          dynamic "env" {
            for_each = var.env_vars
            content {
              name  = env.key
              value = env.value
            }
          }

          # ── Bulk-inject ConfigMap keys ────────────────────────────
          dynamic "env_from" {
            for_each = length(var.config_data) > 0 ? [1] : []
            content {
              config_map_ref {
                name = kubernetes_config_map_v1.this[0].metadata[0].name
              }
            }
          }

          # ── Bulk-inject Secret keys (module-managed or external) ─
          dynamic "env_from" {
            for_each = var.external_secret_name != null || length(var.secret_data) > 0 ? [1] : []
            content {
              secret_ref {
                name = var.external_secret_name != null ? var.external_secret_name : kubernetes_secret_v1.this[0].metadata[0].name
              }
            }
          }

          # ── Readiness probe ──────────────────────────────────────
          dynamic "readiness_probe" {
            for_each = var.readiness_probe != null ? [var.readiness_probe] : []
            content {
              http_get {
                path = readiness_probe.value.path
                port = coalesce(readiness_probe.value.port, var.container_port)
              }
              initial_delay_seconds = readiness_probe.value.initial_delay_seconds
              period_seconds        = readiness_probe.value.period_seconds
              timeout_seconds       = readiness_probe.value.timeout_seconds
              failure_threshold     = readiness_probe.value.failure_threshold
            }
          }

          # ── Liveness probe ───────────────────────────────────────
          dynamic "liveness_probe" {
            for_each = var.liveness_probe != null ? [var.liveness_probe] : []
            content {
              http_get {
                path = liveness_probe.value.path
                port = coalesce(liveness_probe.value.port, var.container_port)
              }
              initial_delay_seconds = liveness_probe.value.initial_delay_seconds
              period_seconds        = liveness_probe.value.period_seconds
              timeout_seconds       = liveness_probe.value.timeout_seconds
              failure_threshold     = liveness_probe.value.failure_threshold
            }
          }
        }

        # ── Pod anti-affinity (spread across nodes) ──────────────
        dynamic "affinity" {
          for_each = var.enable_pod_anti_affinity ? [1] : []
          content {
            pod_anti_affinity {
              preferred_during_scheduling_ignored_during_execution {
                weight = 100
                pod_affinity_term {
                  label_selector {
                    match_labels = local.selector_labels
                  }
                  topology_key = "kubernetes.io/hostname"
                }
              }
            }
          }
        }
      }
    }
  }

  # ── Preconditions ────────────────────────────────────────────────
  lifecycle {
    precondition {
      condition     = var.environment != "prod" || var.readiness_probe != null
      error_message = "readiness_probe is required for prod deployments."
    }
    precondition {
      condition     = var.environment != "prod" || var.liveness_probe != null
      error_message = "liveness_probe is required for prod deployments."
    }
    precondition {
      condition     = !var.enable_irsa || var.iam_role_arn != ""
      error_message = "iam_role_arn is required when enable_irsa = true."
    }
  }
}

# ─────────────────────────────────────────────────────────────────────
# Service
# ─────────────────────────────────────────────────────────────────────

resource "kubernetes_service_v1" "this" {
  metadata {
    name      = var.name
    namespace = local.namespace
    labels    = local.common_labels
  }

  spec {
    type     = var.service_type
    selector = local.selector_labels

    port {
      port        = var.service_port
      target_port = var.container_port
      protocol    = "TCP"
    }
  }
}
