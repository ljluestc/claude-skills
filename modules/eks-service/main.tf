terraform {
  required_version = ">= 1.7.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.25"
    }
  }
}

locals {
  labels = merge(var.common_labels, {
    "app.kubernetes.io/name"       = var.app_name
    "app.kubernetes.io/managed-by" = "terraform"
    "environment"                  = var.environment
  })
}

# --- Namespace ---

resource "kubernetes_namespace" "this" {
  metadata {
    name   = var.namespace
    labels = local.labels
  }
}

# --- ServiceAccount (IRSA) ---

resource "kubernetes_service_account" "this" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.this.metadata[0].name

    annotations = {
      "eks.amazonaws.com/role-arn" = var.iam_role_arn
    }

    labels = local.labels
  }
}

# --- Deployment ---

resource "kubernetes_deployment" "this" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        "app.kubernetes.io/name" = var.app_name
      }
    }

    template {
      metadata {
        labels = local.labels
      }

      spec {
        service_account_name = kubernetes_service_account.this.metadata[0].name

        container {
          name  = var.app_name
          image = var.container_image

          port {
            container_port = var.container_port
          }

          resources {
            requests = {
              cpu    = var.cpu_request
              memory = var.memory_request
            }
            limits = {
              cpu    = var.cpu_limit
              memory = var.memory_limit
            }
          }
        }
      }
    }
  }
}

# --- Service ---

resource "kubernetes_service" "this" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    selector = {
      "app.kubernetes.io/name" = var.app_name
    }

    type = var.service_type

    port {
      port        = var.service_port
      target_port = var.container_port
      protocol    = "TCP"
    }
  }
}

# --- HPA ---

resource "kubernetes_horizontal_pod_autoscaler_v2" "this" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    min_replicas = var.hpa_min_replicas
    max_replicas = var.hpa_max_replicas

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.this.metadata[0].name
    }

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
  }
}

# --- Ingress (conditional) ---

resource "kubernetes_ingress_v1" "this" {
  count = var.ingress_enabled ? 1 : 0

  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.this.metadata[0].name
    labels    = local.labels

    annotations = {
      "kubernetes.io/ingress.class" = "alb"
    }
  }

  spec {
    rule {
      host = var.ingress_host

      http {
        path {
          path      = var.ingress_path
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.this.metadata[0].name
              port {
                number = var.service_port
              }
            }
          }
        }
      }
    }
  }
}
