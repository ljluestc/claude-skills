mock_provider "kubernetes" {}

variables {
  name        = "my-service"
  namespace   = "my-service"
  environment = "dev"
  image       = "nginx"
  image_tag   = "1.27"

  resources = {
    requests = { cpu = "100m", memory = "128Mi" }
    limits   = { cpu = "500m", memory = "512Mi" }
  }

  replicas      = 3
  container_port = 8080
  service_type  = "ClusterIP"
  service_port  = 80

  enable_hpa       = true
  hpa_min_replicas = 2
  hpa_max_replicas = 10
  hpa_cpu_target   = 70

  enable_irsa  = true
  iam_role_arn = "arn:aws:iam::123456789012:role/my-service-role"

  enable_ingress = false
  ingress_host   = ""
  ingress_path   = "/"

  enable_pdb = true
}

run "namespace_is_created_with_correct_name" {
  command = plan

  assert {
    condition     = length(kubernetes_namespace_v1.this) == 1
    error_message = "Namespace should be created when create_namespace is true"
  }

  assert {
    condition     = kubernetes_namespace_v1.this[0].metadata[0].name == "my-service"
    error_message = "Namespace name should match input"
  }
}

run "deployment_replicas_match_input" {
  command = plan

  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].replicas == null
    error_message = "Deployment replicas should be null when HPA is enabled"
  }
}

run "container_image_is_set_correctly" {
  command = plan

  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].image == "nginx:1.27"
    error_message = "Container image should match image:image_tag"
  }
}

run "resource_requests_and_limits_are_applied" {
  command = plan

  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].resources[0].requests["cpu"] == "100m"
    error_message = "CPU request should be 100m"
  }

  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].resources[0].limits["memory"] == "512Mi"
    error_message = "Memory limit should be 512Mi"
  }
}

run "service_type_and_ports_are_correct" {
  command = plan

  assert {
    condition     = kubernetes_service_v1.this.spec[0].type == "ClusterIP"
    error_message = "Service type should be ClusterIP"
  }

  assert {
    condition     = kubernetes_service_v1.this.spec[0].port[0].port == 80
    error_message = "Service port should be 80"
  }

  assert {
    condition     = kubernetes_service_v1.this.spec[0].port[0].target_port == "8080"
    error_message = "Target port should map to container port"
  }
}

run "hpa_min_max_and_cpu_target_applied" {
  command = plan

  assert {
    condition     = length(kubernetes_horizontal_pod_autoscaler_v2.this) == 1
    error_message = "HPA should be created when enable_hpa is true"
  }

  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this[0].spec[0].min_replicas == 2
    error_message = "HPA min replicas should be 2"
  }

  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this[0].spec[0].max_replicas == 10
    error_message = "HPA max replicas should be 10"
  }

  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this[0].spec[0].metric[0].resource[0].target[0].average_utilization == 70
    error_message = "HPA CPU target should be 70"
  }
}

run "service_account_has_irsa_annotation" {
  command = plan

  assert {
    condition     = length(kubernetes_service_account_v1.this) == 1
    error_message = "Service account should be created when IRSA is enabled"
  }

  assert {
    condition     = kubernetes_service_account_v1.this[0].metadata[0].annotations["eks.amazonaws.com/role-arn"] == "arn:aws:iam::123456789012:role/my-service-role"
    error_message = "IRSA annotation should contain role ARN"
  }
}

run "ingress_not_created_when_disabled" {
  command = plan

  assert {
    condition     = length(kubernetes_ingress_v1.this) == 0
    error_message = "Ingress should not be created by default"
  }
}

run "ingress_created_with_host_and_path" {
  command = plan

  variables {
    enable_ingress = true
    ingress_host   = "api.example.com"
    ingress_path   = "/v1"
  }

  assert {
    condition     = length(kubernetes_ingress_v1.this) == 1
    error_message = "Ingress should be created when enabled"
  }

  assert {
    condition     = kubernetes_ingress_v1.this[0].spec[0].rule[0].host == "api.example.com"
    error_message = "Ingress host should match input"
  }

  assert {
    condition     = kubernetes_ingress_v1.this[0].spec[0].rule[0].http[0].path[0].path == "/v1"
    error_message = "Ingress path should match input"
  }
}


run "external_secret_name_overrides_managed_secret_creation" {
  command = plan

  variables {
    external_secret_name = "my-eso-secret"
    secret_data = {
      SHOULD_NOT_CREATE = "true"
    }
  }

  assert {
    condition     = length(kubernetes_secret_v1.this) == 0
    error_message = "Managed Secret must not be created when external_secret_name is set"
  }

  assert {
    condition     = length(kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].env_from) == 1
    error_message = "Deployment should attach exactly one secret envFrom source in this scenario"
  }

  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].env_from[0].secret_ref[0].name == "my-eso-secret"
    error_message = "Deployment should reference external_secret_name when provided"
  }
}

run "managed_secret_created_when_external_secret_is_absent" {
  command = plan

  variables {
    secret_data = {
      API_KEY = "super-secret"
    }
  }

  assert {
    condition     = length(kubernetes_secret_v1.this) == 1
    error_message = "Managed Secret should be created when secret_data is provided and external_secret_name is null"
  }

  assert {
    condition     = length(kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].env_from) == 1
    error_message = "Deployment should attach one secret envFrom source when managed secret is created"
  }

  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].env_from[0].secret_ref[0].name == kubernetes_secret_v1.this[0].metadata[0].name
    error_message = "Deployment should reference module-managed Secret when external_secret_name is absent"
  }
}

run "no_secret_env_from_when_external_and_secret_data_absent" {
  command = plan

  variables {
    external_secret_name = null
    secret_data          = {}
  }

  assert {
    condition     = length(kubernetes_secret_v1.this) == 0
    error_message = "Managed Secret should not be created when secret_data is empty and no external secret is provided"
  }

  assert {
    condition     = length(kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].env_from) == 0
    error_message = "Deployment should not attach secret envFrom when both external_secret_name and secret_data are absent"
  }
}
run "dev_environment_behavior" {
  command = plan

  variables {
    environment      = "dev"
    enable_hpa       = true
    hpa_min_replicas = null
    hpa_max_replicas = null
    replicas         = null
    enable_irsa      = false
  }

  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this[0].spec[0].min_replicas == 1
    error_message = "Dev default HPA min should be 1"
  }

  assert {
    condition     = output.service_account_name == ""
    error_message = "Service account output should be empty when IRSA disabled"
  }
}

run "prod_environment_behavior" {
  command = plan

  variables {
    environment      = "prod"
    readiness_probe  = { path = "/readyz" }
    liveness_probe   = { path = "/livez" }
    enable_hpa       = true
    hpa_min_replicas = null
    hpa_max_replicas = null
    service_type     = "LoadBalancer"
    enable_ingress   = true
    ingress_host     = "api.prod.example.com"
  }

  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this[0].spec[0].min_replicas == 3
    error_message = "Prod default HPA min should be 3"
  }

  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this[0].spec[0].max_replicas == 10
    error_message = "Prod default HPA max should be 10"
  }

  assert {
    condition     = kubernetes_service_v1.this.spec[0].type == "LoadBalancer"
    error_message = "Prod service can be LoadBalancer"
  }

  assert {
    condition     = output.ingress_hostname == "api.prod.example.com"
    error_message = "Ingress output should match configured host"
  }
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

run "reject_invalid_environment" {
  command = plan

  variables {
    environment = "banana"
  }

  expect_failures = [
    var.environment
  ]
}

run "prod_requires_probes" {
  command = plan

  variables {
    environment     = "prod"
    readiness_probe = null
    liveness_probe  = null
  }

  expect_failures = [
    kubernetes_deployment_v1.this
  ]
}

run "irsa_requires_role_arn" {
  command = plan

  variables {
    enable_irsa  = true
    iam_role_arn = ""
  }

  expect_failures = [
    kubernetes_deployment_v1.this
  ]
}

run "outputs_are_correct" {
  command = plan

  assert {
    condition     = output.namespace == "my-service"
    error_message = "namespace output should match input namespace"
  }

  assert {
    condition     = output.deployment_name == "my-service"
    error_message = "deployment_name output should match service name"
  }

  assert {
    condition     = output.service_name == "my-service"
    error_message = "service_name output should match service name"
  }

  assert {
    condition     = output.service_account_name == "my-service"
    error_message = "service_account_name output should match when IRSA enabled"
  }

  assert {
    condition     = output.service_fqdn == "my-service.my-service.svc.cluster.local"
    error_message = "service_fqdn output should be rendered correctly"
  }
}
