resource "kubernetes_config_map_v1" "this" {
  count = length(var.config_data) > 0 ? 1 : 0

  metadata {
    name      = var.name
    namespace = local.namespace
    labels    = local.common_labels
  }

  data = var.config_data
}

resource "kubernetes_secret_v1" "this" {
  # external_secret_name takes precedence over secret_data:
  # - external set   => do not create module-managed Secret
  # - external unset => create only when secret_data is non-empty
  count = (
    var.external_secret_name == null &&
    length(var.secret_data) > 0
  ) ? 1 : 0

  metadata {
    name      = var.name
    namespace = local.namespace
    labels    = local.common_labels
  }

  data = var.secret_data
  type = "Opaque"
}
