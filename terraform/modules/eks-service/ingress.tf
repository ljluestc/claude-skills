resource "kubernetes_ingress_v1" "this" {
  count = var.enable_ingress ? 1 : 0

  metadata {
    name      = var.name
    namespace = local.namespace
    labels    = local.common_labels

    annotations = merge(
      { "kubernetes.io/ingress.class" = var.ingress_class },
      var.ingress_annotations,
    )
  }

  spec {
    # TLS termination (opt-in)
    dynamic "tls" {
      for_each = var.ingress_tls_secret != null ? [1] : []
      content {
        hosts       = [var.ingress_host]
        secret_name = var.ingress_tls_secret
      }
    }

    rule {
      host = var.ingress_host

      http {
        path {
          path      = var.ingress_path
          path_type = var.ingress_path_type

          backend {
            service {
              name = kubernetes_service_v1.this.metadata[0].name
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
