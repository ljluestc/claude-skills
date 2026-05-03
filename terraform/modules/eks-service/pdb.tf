resource "kubernetes_pod_disruption_budget_v1" "this" {
  count = var.enable_pdb ? 1 : 0

  metadata {
    name      = var.name
    namespace = local.namespace
    labels    = local.common_labels
  }

  spec {
    min_available = var.pdb_min_available

    selector {
      match_labels = local.selector_labels
    }
  }
}
