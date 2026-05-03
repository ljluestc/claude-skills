output "namespace" {
  description = "Kubernetes namespace the service is deployed in."
  value       = local.namespace
}

output "deployment_name" {
  description = "Name of the Kubernetes Deployment."
  value       = kubernetes_deployment_v1.this.metadata[0].name
}

output "service_name" {
  description = "Name of the Kubernetes Service."
  value       = kubernetes_service_v1.this.metadata[0].name
}

output "service_cluster_ip" {
  description = "ClusterIP assigned to the Kubernetes Service."
  value       = kubernetes_service_v1.this.spec[0].cluster_ip
}

output "service_account_name" {
  description = "Name of the IRSA ServiceAccount (empty string when IRSA is disabled)."
  value       = var.enable_irsa ? kubernetes_service_account_v1.this[0].metadata[0].name : ""
}

output "ingress_hostname" {
  description = "Ingress hostname (empty string when ingress is disabled)."
  value       = var.enable_ingress ? var.ingress_host : ""
}

output "selector_labels" {
  description = "Labels used in the Deployment selector — useful for PodDisruptionBudgets."
  value       = local.selector_labels
}

output "service_fqdn" {
  description = "Cluster-internal FQDN for cross-namespace or service-mesh routing."
  value       = "${var.name}.${local.namespace}.svc.cluster.local"
}
