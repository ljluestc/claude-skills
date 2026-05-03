# =============================================================================
# EKS Service Module — Integration Tests (apply mode, real cluster required)
# Requires: Valid kubeconfig pointing to a test EKS cluster
# Run:      terraform test -filter=tests/eks_service_integration_test.tftest.hcl -verbose
# =============================================================================

variables {
  namespace       = "integ-test-svc"
  app_name        = "integ-test-svc"
  container_image = "nginx:1.25"
  replicas        = 2
  container_port  = 80
  service_type    = "ClusterIP"
  service_port    = 80
  cpu_request     = "50m"
  cpu_limit       = "200m"
  memory_request  = "64Mi"
  memory_limit    = "128Mi"
  hpa_min_replicas = 1
  hpa_max_replicas = 4
  hpa_cpu_target   = 80
  iam_role_arn    = "arn:aws:iam::123456789012:role/integ-test-role"
  ingress_enabled = false
  environment     = "dev"
  common_labels   = {}
}

run "creates_namespace_on_cluster" {
  # command defaults to apply — creates real K8s resources

  assert {
    condition     = kubernetes_namespace.this.metadata[0].name == "integ-test-svc"
    error_message = "Namespace should be created on the cluster"
  }
}

run "creates_deployment_on_cluster" {
  assert {
    condition     = kubernetes_deployment.this.metadata[0].name == "integ-test-svc"
    error_message = "Deployment should exist on the cluster"
  }

  assert {
    condition     = kubernetes_deployment.this.spec[0].replicas == 2
    error_message = "Deployment should have 2 replicas"
  }
}

run "creates_service_on_cluster" {
  assert {
    condition     = kubernetes_service.this.spec[0].type == "ClusterIP"
    error_message = "Service type should be ClusterIP"
  }
}

run "creates_hpa_on_cluster" {
  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].min_replicas == 1
    error_message = "HPA min replicas should be 1"
  }

  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].max_replicas == 4
    error_message = "HPA max replicas should be 4"
  }
}

run "service_account_created_with_irsa" {
  assert {
    condition     = kubernetes_service_account.this.metadata[0].annotations["eks.amazonaws.com/role-arn"] == "arn:aws:iam::123456789012:role/integ-test-role"
    error_message = "Service account should have IRSA annotation"
  }
}

# Cleanup destroys in reverse order automatically after all run blocks complete.
