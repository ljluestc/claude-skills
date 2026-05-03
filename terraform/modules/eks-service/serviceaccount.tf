resource "kubernetes_service_account_v1" "this" {
  count = var.enable_irsa ? 1 : 0

  metadata {
    name      = var.name
    namespace = local.namespace
    labels    = local.common_labels

    annotations = {
      "eks.amazonaws.com/role-arn" = var.iam_role_arn
    }
  }

  automount_service_account_token = true
}
