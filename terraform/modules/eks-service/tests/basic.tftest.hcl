mock_provider "kubernetes" {}

# ─────────────────────────────────────────────────────────────────────
# Minimal dev deployment — should plan without errors
# ─────────────────────────────────────────────────────────────────────

variables {
  name        = "test-svc"
  namespace   = "test-ns"
  environment = "dev"
  image       = "nginx"
  image_tag   = "1.27-alpine"

  resources = {
    requests = { cpu = "100m", memory = "128Mi" }
    limits   = { cpu = "200m", memory = "256Mi" }
  }
}

run "creates_deployment_and_service" {
  command = plan

  assert {
    condition     = output.deployment_name == "test-svc"
    error_message = "Deployment name should match var.name"
  }

  assert {
    condition     = output.namespace == "test-ns"
    error_message = "Namespace should match var.namespace"
  }

  assert {
    condition     = output.service_name == "test-svc"
    error_message = "Service name should match var.name"
  }

  assert {
    condition     = output.service_fqdn == "test-svc.test-ns.svc.cluster.local"
    error_message = "Service FQDN should follow <name>.<ns>.svc.cluster.local"
  }
}

# ─────────────────────────────────────────────────────────────────────
# PDB is created by default
# ─────────────────────────────────────────────────────────────────────

run "pdb_enabled_by_default" {
  command = plan

  assert {
    condition     = length(kubernetes_pod_disruption_budget_v1.this) == 1
    error_message = "PDB should be created when enable_pdb defaults to true"
  }
}

# ─────────────────────────────────────────────────────────────────────
# Security context defaults are secure
# ─────────────────────────────────────────────────────────────────────

run "secure_defaults_applied" {
  command = plan

  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].security_context[0].run_as_non_root == true
    error_message = "Pod should run as non-root by default"
  }

  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].security_context[0].allow_privilege_escalation == false
    error_message = "Container should deny privilege escalation by default"
  }

  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].security_context[0].read_only_root_filesystem == true
    error_message = "Container should have read-only root filesystem by default"
  }
}

# ─────────────────────────────────────────────────────────────────────
# Prod without probes should fail precondition
# ─────────────────────────────────────────────────────────────────────

run "prod_requires_probes" {
  command = plan

  variables {
    environment = "prod"
    # deliberately omitting readiness_probe and liveness_probe
  }

  expect_failures = [
    kubernetes_deployment_v1.this,
  ]
}

# ─────────────────────────────────────────────────────────────────────
# IRSA without role ARN should fail precondition
# ─────────────────────────────────────────────────────────────────────

run "irsa_requires_role_arn" {
  command = plan

  variables {
    enable_irsa  = true
    iam_role_arn = ""
  }

  expect_failures = [
    kubernetes_deployment_v1.this,
  ]
}
