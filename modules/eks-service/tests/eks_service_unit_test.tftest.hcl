# =============================================================================
# EKS Service Module — Unit Tests (plan mode, no cluster required)
# Requires: Terraform >= 1.7.0 (for mock_provider)
# Run:      terraform test -filter=tests/eks_service_unit_test.tftest.hcl
# =============================================================================

# ---------------------------------------------------------------------------
# Mock the Kubernetes provider so tests run without a real cluster
# ---------------------------------------------------------------------------
mock_provider "kubernetes" {}

# ---------------------------------------------------------------------------
# File-level defaults — shared across all run blocks
# ---------------------------------------------------------------------------
variables {
  namespace       = "my-service"
  app_name        = "my-service"
  container_image = "my-service:v1.0.0"
  replicas        = 3
  container_port  = 8080
  service_type    = "ClusterIP"
  service_port    = 80
  cpu_request     = "100m"
  cpu_limit       = "500m"
  memory_request  = "128Mi"
  memory_limit    = "512Mi"
  hpa_min_replicas = 2
  hpa_max_replicas = 10
  hpa_cpu_target   = 70
  iam_role_arn    = "arn:aws:iam::123456789012:role/my-service-role"
  ingress_enabled = false
  ingress_host    = ""
  ingress_path    = "/"
  environment     = "dev"
  common_labels   = {}
}

# =====================================================================
# 1. BASIC VALIDATION — Namespace, Deployment, Image, Resources
# =====================================================================

run "namespace_is_created_with_correct_name" {
  command = plan

  assert {
    condition     = kubernetes_namespace.this.metadata[0].name == "my-service"
    error_message = "Namespace name should be 'my-service', got '${kubernetes_namespace.this.metadata[0].name}'"
  }
}

run "deployment_replicas_match_input" {
  command = plan

  assert {
    condition     = kubernetes_deployment.this.spec[0].replicas == 3
    error_message = "Deployment replicas should be 3"
  }
}

run "container_image_is_set_correctly" {
  command = plan

  assert {
    condition     = kubernetes_deployment.this.spec[0].template[0].spec[0].container[0].image == "my-service:v1.0.0"
    error_message = "Container image should be 'my-service:v1.0.0'"
  }
}

run "resource_requests_are_applied" {
  command = plan

  assert {
    condition     = kubernetes_deployment.this.spec[0].template[0].spec[0].container[0].resources[0].requests["cpu"] == "100m"
    error_message = "CPU request should be '100m'"
  }

  assert {
    condition     = kubernetes_deployment.this.spec[0].template[0].spec[0].container[0].resources[0].requests["memory"] == "128Mi"
    error_message = "Memory request should be '128Mi'"
  }
}

run "resource_limits_are_applied" {
  command = plan

  assert {
    condition     = kubernetes_deployment.this.spec[0].template[0].spec[0].container[0].resources[0].limits["cpu"] == "500m"
    error_message = "CPU limit should be '500m'"
  }

  assert {
    condition     = kubernetes_deployment.this.spec[0].template[0].spec[0].container[0].resources[0].limits["memory"] == "512Mi"
    error_message = "Memory limit should be '512Mi'"
  }
}

run "labels_include_app_name_and_environment" {
  command = plan

  assert {
    condition     = kubernetes_deployment.this.metadata[0].labels["app.kubernetes.io/name"] == "my-service"
    error_message = "Deployment should have app.kubernetes.io/name label"
  }

  assert {
    condition     = kubernetes_deployment.this.metadata[0].labels["environment"] == "dev"
    error_message = "Deployment should have environment label set to 'dev'"
  }

  assert {
    condition     = kubernetes_deployment.this.metadata[0].labels["app.kubernetes.io/managed-by"] == "terraform"
    error_message = "Deployment should have managed-by=terraform label"
  }
}

# =====================================================================
# 2. SERVICE — Type, Port Mappings
# =====================================================================

run "service_type_defaults_to_clusterip" {
  command = plan

  assert {
    condition     = kubernetes_service.this.spec[0].type == "ClusterIP"
    error_message = "Service type should default to ClusterIP"
  }
}

run "service_port_mapping_is_correct" {
  command = plan

  assert {
    condition     = kubernetes_service.this.spec[0].port[0].port == 80
    error_message = "Service port should be 80"
  }

  assert {
    condition     = kubernetes_service.this.spec[0].port[0].target_port == "8080"
    error_message = "Service target port should be 8080"
  }

  assert {
    condition     = kubernetes_service.this.spec[0].port[0].protocol == "TCP"
    error_message = "Service protocol should be TCP"
  }
}

run "service_type_loadbalancer_when_specified" {
  command = plan

  variables {
    service_type = "LoadBalancer"
  }

  assert {
    condition     = kubernetes_service.this.spec[0].type == "LoadBalancer"
    error_message = "Service type should be LoadBalancer when overridden"
  }
}

run "service_selector_matches_app_name" {
  command = plan

  assert {
    condition     = kubernetes_service.this.spec[0].selector["app.kubernetes.io/name"] == "my-service"
    error_message = "Service selector should match app name"
  }
}

# =====================================================================
# 3. HPA — Min/Max Replicas, CPU Target
# =====================================================================

run "hpa_min_replicas_respected" {
  command = plan

  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].min_replicas == 2
    error_message = "HPA min replicas should be 2"
  }
}

run "hpa_max_replicas_respected" {
  command = plan

  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].max_replicas == 10
    error_message = "HPA max replicas should be 10"
  }
}

run "hpa_cpu_target_applied" {
  command = plan

  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].metric[0].resource[0].target[0].average_utilization == 70
    error_message = "HPA CPU target should be 70%"
  }
}

run "hpa_targets_the_deployment" {
  command = plan

  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].scale_target_ref[0].kind == "Deployment"
    error_message = "HPA should target a Deployment"
  }

  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].scale_target_ref[0].name == "my-service"
    error_message = "HPA should target the 'my-service' deployment"
  }
}

# =====================================================================
# 4. IRSA — ServiceAccount Annotation
# =====================================================================

run "service_account_has_irsa_annotation" {
  command = plan

  assert {
    condition     = kubernetes_service_account.this.metadata[0].annotations["eks.amazonaws.com/role-arn"] == "arn:aws:iam::123456789012:role/my-service-role"
    error_message = "ServiceAccount should have eks.amazonaws.com/role-arn annotation with the IAM role ARN"
  }
}

run "deployment_uses_service_account" {
  command = plan

  assert {
    condition     = kubernetes_deployment.this.spec[0].template[0].spec[0].service_account_name == "my-service"
    error_message = "Deployment should use the IRSA service account"
  }
}

# =====================================================================
# 5. INGRESS — Conditional Creation, Host/Path Config
# =====================================================================

run "ingress_not_created_when_disabled" {
  command = plan

  variables {
    ingress_enabled = false
  }

  assert {
    condition     = length(kubernetes_ingress_v1.this) == 0
    error_message = "Ingress should not be created when ingress_enabled = false"
  }
}

run "ingress_created_when_enabled" {
  command = plan

  variables {
    ingress_enabled = true
    ingress_host    = "api.example.com"
    ingress_path    = "/v1"
  }

  assert {
    condition     = length(kubernetes_ingress_v1.this) == 1
    error_message = "Ingress should be created when ingress_enabled = true"
  }

  assert {
    condition     = kubernetes_ingress_v1.this[0].spec[0].rule[0].host == "api.example.com"
    error_message = "Ingress host should be 'api.example.com'"
  }

  assert {
    condition     = kubernetes_ingress_v1.this[0].spec[0].rule[0].http[0].path[0].path == "/v1"
    error_message = "Ingress path should be '/v1'"
  }

  assert {
    condition     = kubernetes_ingress_v1.this[0].spec[0].rule[0].http[0].path[0].path_type == "Prefix"
    error_message = "Ingress path type should be 'Prefix'"
  }
}

run "ingress_has_alb_annotation" {
  command = plan

  variables {
    ingress_enabled = true
    ingress_host    = "api.example.com"
  }

  assert {
    condition     = kubernetes_ingress_v1.this[0].metadata[0].annotations["kubernetes.io/ingress.class"] == "alb"
    error_message = "Ingress should have ALB ingress class annotation"
  }
}

# =====================================================================
# 6. ENVIRONMENT-SPECIFIC — Dev vs Prod Configurations
# =====================================================================

run "dev_environment_config" {
  command = plan

  variables {
    environment      = "dev"
    replicas         = 1
    hpa_min_replicas = 1
    hpa_max_replicas = 3
    cpu_request      = "50m"
    memory_request   = "64Mi"
    ingress_enabled  = false
  }

  assert {
    condition     = kubernetes_deployment.this.spec[0].replicas == 1
    error_message = "Dev should have 1 replica"
  }

  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].max_replicas == 3
    error_message = "Dev HPA max should be 3"
  }

  assert {
    condition     = kubernetes_deployment.this.spec[0].template[0].spec[0].container[0].resources[0].requests["cpu"] == "50m"
    error_message = "Dev CPU request should be 50m"
  }

  assert {
    condition     = length(kubernetes_ingress_v1.this) == 0
    error_message = "Dev should not have ingress"
  }
}

run "prod_environment_config" {
  command = plan

  variables {
    environment      = "prod"
    replicas         = 5
    hpa_min_replicas = 3
    hpa_max_replicas = 20
    hpa_cpu_target   = 60
    cpu_request      = "250m"
    cpu_limit        = "1000m"
    memory_request   = "256Mi"
    memory_limit     = "1Gi"
    service_type     = "LoadBalancer"
    ingress_enabled  = true
    ingress_host     = "api.prod.example.com"
    ingress_path     = "/"
  }

  assert {
    condition     = kubernetes_deployment.this.spec[0].replicas == 5
    error_message = "Prod should have 5 replicas"
  }

  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].min_replicas == 3
    error_message = "Prod HPA min should be 3"
  }

  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].max_replicas == 20
    error_message = "Prod HPA max should be 20"
  }

  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].metric[0].resource[0].target[0].average_utilization == 60
    error_message = "Prod HPA CPU target should be 60%"
  }

  assert {
    condition     = kubernetes_service.this.spec[0].type == "LoadBalancer"
    error_message = "Prod service should be LoadBalancer"
  }

  assert {
    condition     = length(kubernetes_ingress_v1.this) == 1
    error_message = "Prod should have ingress"
  }

  assert {
    condition     = kubernetes_ingress_v1.this[0].spec[0].rule[0].host == "api.prod.example.com"
    error_message = "Prod ingress host should be 'api.prod.example.com'"
  }

  assert {
    condition     = kubernetes_deployment.this.metadata[0].labels["environment"] == "prod"
    error_message = "Prod resources should have environment=prod label"
  }
}

# =====================================================================
# 7. NEGATIVE TESTS — Invalid Inputs Should Fail
# =====================================================================

run "reject_invalid_namespace" {
  command = plan

  variables {
    namespace = "INVALID_NAMESPACE!"
  }

  expect_failures = [
    var.namespace
  ]
}

run "reject_image_without_tag" {
  command = plan

  variables {
    container_image = "my-service"
  }

  expect_failures = [
    var.container_image
  ]
}

run "reject_invalid_service_type" {
  command = plan

  variables {
    service_type = "ExternalName"
  }

  expect_failures = [
    var.service_type
  ]
}

run "reject_replicas_out_of_range" {
  command = plan

  variables {
    replicas = 100
  }

  expect_failures = [
    var.replicas
  ]
}

run "reject_invalid_environment" {
  command = plan

  variables {
    environment = "banana"
  }

  expect_failures = [
    var.environment
  ]
}

run "reject_invalid_iam_role_arn" {
  command = plan

  variables {
    iam_role_arn = "not-an-arn"
  }

  expect_failures = [
    var.iam_role_arn
  ]
}

run "reject_hpa_cpu_target_zero" {
  command = plan

  variables {
    hpa_cpu_target = 0
  }

  expect_failures = [
    var.hpa_cpu_target
  ]
}

run "reject_hpa_cpu_target_over_100" {
  command = plan

  variables {
    hpa_cpu_target = 150
  }

  expect_failures = [
    var.hpa_cpu_target
  ]
}

# =====================================================================
# 8. OUTPUT ASSERTIONS
# =====================================================================

run "outputs_are_correct" {
  command = plan

  assert {
    condition     = output.namespace_name == "my-service"
    error_message = "namespace_name output should be 'my-service'"
  }

  assert {
    condition     = output.deployment_name == "my-service"
    error_message = "deployment_name output should be 'my-service'"
  }

  assert {
    condition     = output.service_name == "my-service"
    error_message = "service_name output should be 'my-service'"
  }

  assert {
    condition     = output.service_type == "ClusterIP"
    error_message = "service_type output should be 'ClusterIP'"
  }

  assert {
    condition     = output.service_account_name == "my-service"
    error_message = "service_account_name output should be 'my-service'"
  }

  assert {
    condition     = output.service_account_arn == "arn:aws:iam::123456789012:role/my-service-role"
    error_message = "service_account_arn output should match IAM role ARN"
  }

  assert {
    condition     = output.hpa_min_replicas == 2
    error_message = "hpa_min_replicas output should be 2"
  }

  assert {
    condition     = output.hpa_max_replicas == 10
    error_message = "hpa_max_replicas output should be 10"
  }

  assert {
    condition     = output.ingress_enabled == false
    error_message = "ingress_enabled output should be false"
  }

  assert {
    condition     = output.ingress_host == ""
    error_message = "ingress_host output should be empty when disabled"
  }
}

run "outputs_with_ingress_enabled" {
  command = plan

  variables {
    ingress_enabled = true
    ingress_host    = "api.example.com"
  }

  assert {
    condition     = output.ingress_enabled == true
    error_message = "ingress_enabled output should be true"
  }

  assert {
    condition     = output.ingress_host == "api.example.com"
    error_message = "ingress_host output should be 'api.example.com'"
  }
}
