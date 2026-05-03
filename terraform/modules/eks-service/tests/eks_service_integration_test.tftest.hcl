variables {
  name        = "integ-test-svc"
  namespace   = "integ-test-svc"
  environment = "dev"
  image       = "nginx"
  image_tag   = "1.27"

  resources = {
    requests = { cpu = "50m", memory = "64Mi" }
    limits   = { cpu = "200m", memory = "256Mi" }
  }

  enable_hpa       = true
  hpa_min_replicas = 1
  hpa_max_replicas = 4
  hpa_cpu_target   = 80

  enable_irsa  = true
  iam_role_arn = "arn:aws:iam::123456789012:role/integ-test-role"

  enable_ingress = false
}

run "creates_namespace" {
  assert {
    condition     = output.namespace == "integ-test-svc"
    error_message = "Namespace should be created on the target cluster"
  }
}

run "creates_deployment_and_service" {
  assert {
    condition     = kubernetes_deployment_v1.this.metadata[0].name == "integ-test-svc"
    error_message = "Deployment should exist"
  }

  assert {
    condition     = kubernetes_service_v1.this.metadata[0].name == "integ-test-svc"
    error_message = "Service should exist"
  }
}

run "creates_hpa_and_irsa_resources" {
  assert {
    condition     = length(kubernetes_horizontal_pod_autoscaler_v2.this) == 1
    error_message = "HPA should exist"
  }

  assert {
    condition     = length(kubernetes_service_account_v1.this) == 1
    error_message = "Service account should exist"
  }

  assert {
    condition     = kubernetes_service_account_v1.this[0].metadata[0].annotations["eks.amazonaws.com/role-arn"] == "arn:aws:iam::123456789012:role/integ-test-role"
    error_message = "Service account should contain expected IRSA role ARN"
  }
}
