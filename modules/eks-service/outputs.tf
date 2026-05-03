output "namespace_name" {
  description = "Name of the created namespace"
  value       = kubernetes_namespace.this.metadata[0].name
}

output "deployment_name" {
  description = "Name of the deployment"
  value       = kubernetes_deployment.this.metadata[0].name
}

output "service_name" {
  description = "Name of the Kubernetes service"
  value       = kubernetes_service.this.metadata[0].name
}

output "service_type" {
  description = "Type of the Kubernetes service"
  value       = kubernetes_service.this.spec[0].type
}

output "service_account_name" {
  description = "Name of the IRSA service account"
  value       = kubernetes_service_account.this.metadata[0].name
}

output "service_account_arn" {
  description = "IAM role ARN attached to the service account"
  value       = kubernetes_service_account.this.metadata[0].annotations["eks.amazonaws.com/role-arn"]
}

output "hpa_min_replicas" {
  description = "HPA minimum replicas"
  value       = kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].min_replicas
}

output "hpa_max_replicas" {
  description = "HPA maximum replicas"
  value       = kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].max_replicas
}

output "ingress_enabled" {
  description = "Whether ingress was created"
  value       = var.ingress_enabled
}

output "ingress_host" {
  description = "Ingress hostname (empty if ingress disabled)"
  value       = var.ingress_enabled ? kubernetes_ingress_v1.this[0].spec[0].rule[0].host : ""
}
