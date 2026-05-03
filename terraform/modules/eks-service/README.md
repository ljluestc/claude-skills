# eks-service

Reusable Terraform module for deploying a Kubernetes service on AWS EKS.

Provisions a Namespace, Deployment, Service, and optionally an HPA, Ingress, ConfigMap, Secret, IRSA-annotated ServiceAccount, and PodDisruptionBudget — all driven by environment-aware defaults and secure-by-default runtime settings.

## File Structure

```
modules/eks-service/
├── main.tf            # Deployment + Service
├── variables.tf       # All input variables with types and validations
├── outputs.tf         # Outputs consumers need
├── versions.tf        # terraform {} block with required_providers
├── locals.tf          # Environment defaults, labels, computed values
├── namespace.tf       # Conditional namespace creation
├── config.tf          # ConfigMap + Secret
├── serviceaccount.tf  # IRSA service account
├── hpa.tf             # HorizontalPodAutoscaler
├── ingress.tf         # Optional Ingress
├── pdb.tf             # Optional PodDisruptionBudget
├── tests/             # terraform test suites (basic/hpa/ingress)
└── README.md          # This file
```

## Usage — Production Example

```hcl
# Root module — environments/prod/main.tf

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

module "payment_api" {
  source = "../../modules/eks-service"

  # ── Core ───────────────────────────────────────────────────
  name             = "payment-api"
  namespace        = "payments"
  create_namespace = true
  environment      = "prod"

  # ── Container ──────────────────────────────────────────────
  image          = "123456789012.dkr.ecr.us-east-1.amazonaws.com/payment-api"
  image_tag      = "v2.4.1"
  container_port = 8080

  # ── Resources — always explicit, never defaulted ───────────
  resources = {
    requests = { cpu = "250m",  memory = "256Mi" }
    limits   = { cpu = "500m",  memory = "512Mi" }
  }

  # ── Probes ─────────────────────────────────────────────────
  readiness_probe = {
    path                  = "/healthz"
    initial_delay_seconds = 10
    period_seconds        = 5
  }
  liveness_probe = {
    path                  = "/healthz"
    initial_delay_seconds = 30
    period_seconds        = 15
  }

  # ── Autoscaling ────────────────────────────────────────────
  enable_hpa     = true
  hpa_cpu_target = 70
  # min/max default to prod values: 3 / 10
  hpa_scale_up_stabilization   = 60
  hpa_scale_down_stabilization = 300

  # ── Config + Secrets ───────────────────────────────────────
  env_vars = {
    LOG_LEVEL = "info"
    REGION    = "us-east-1"
  }
  config_data = {
    FEATURE_FLAGS = "payments-v2=true,new-checkout=true"
  }
  secret_data = {
    DB_PASSWORD = var.db_password   # comes from Vault / SSM
    API_KEY     = var.api_key
  }

  # Prefer external_secret_name when using ESO/Secrets Store CSI
  # external_secret_name = "payment-api-runtime-secrets"

  # ── IRSA ───────────────────────────────────────────────────
  enable_irsa  = true
  iam_role_arn = module.payment_api_irsa.iam_role_arn

  # ── Reliability / Scheduling / Security ────────────────────
  enable_pdb         = true
  pdb_min_available  = "50%"
  enable_pod_anti_affinity = true

  security_context = {
    run_as_non_root = true
    run_as_user     = 1000
    run_as_group    = 1000
    fs_group        = 1000
  }
  container_security_context = {
    allow_privilege_escalation = false
    read_only_root_filesystem  = true
    run_as_non_root            = true
  }

  rollout_strategy = {
    type            = "RollingUpdate"
    max_surge       = "25%"
    max_unavailable = "0"
  }

  # ── Metrics scraping ────────────────────────────────────────
  enable_prometheus = true
  prometheus_path   = "/metrics"

  # ── Ingress ────────────────────────────────────────────────
  enable_ingress      = true
  ingress_class       = "alb"
  ingress_host        = "api.payments.example.com"
  ingress_tls_secret  = "payments-tls"
  ingress_annotations = {
    "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
    "alb.ingress.kubernetes.io/target-type" = "ip"
  }
}
```

## Secret Source Precedence (`external_secret_name` vs `secret_data`)

This module resolves secret `env_from` in this order:

1. `external_secret_name != null`
   - `kubernetes_secret_v1` is **not created**
   - Deployment `env_from.secret_ref.name` uses `external_secret_name`
   - If `secret_data` is also provided, it is ignored for Secret creation

2. `external_secret_name == null` and `secret_data` is non-empty
   - `kubernetes_secret_v1` is created
   - Deployment `env_from.secret_ref.name` uses that managed Secret

3. `external_secret_name == null` and `secret_data` is empty
   - No `kubernetes_secret_v1` is created
   - Deployment does **not** attach secret `env_from`

## Usage — Minimal Dev Service

```hcl
module "debug_tool" {
  source = "../../modules/eks-service"

  name             = "debug-tool"
  namespace        = "tooling"
  create_namespace = false        # namespace already exists
  environment      = "dev"

  image     = "nginx"
  image_tag = "1.27-alpine"

  resources = {
    requests = { cpu = "50m",  memory = "64Mi" }
    limits   = { cpu = "100m", memory = "128Mi" }
  }
}
```

## Environment Defaults

| Setting          | dev | staging | prod |
|------------------|-----|---------|------|
| replicas         | 1   | 2       | 3    |
| hpa_min_replicas | 1   | 2       | 3    |
| hpa_max_replicas | 3   | 5       | 10   |

All defaults can be overridden by setting the variable explicitly.

---

## Platform-Grade Behavior Included

- **Prod safety gates**: `environment = "prod"` requires both `readiness_probe` and `liveness_probe`.
- **IRSA guardrail**: `enable_irsa = true` requires non-empty `iam_role_arn`.
- **Secure-by-default runtime**: pod and container `security_context` defaults to non-root, no privilege escalation, and read-only root filesystem.
- **Zero-downtime rollout defaults**: RollingUpdate strategy with `max_unavailable = 0`.
- **Node spreading**: preferred pod anti-affinity on `kubernetes.io/hostname`.
- **HPA stability controls**: configurable scale-up/scale-down stabilization windows.
- **PDB support**: optional disruption budget enabled by default.
- **Prometheus hooks**: optional scrape annotations merged into pod annotations.
- **External secret mode**: `external_secret_name` bypasses module-managed Secret creation and is used by `env_from`.
- **Service discovery output**: `service_fqdn` exposes `<name>.<namespace>.svc.cluster.local`.

## Testing

This module includes `terraform test` suites:

- `tests/eks_service_unit_test.tftest.hcl` — comprehensive unit coverage, including secret precedence behavior
- `tests/eks_service_integration_test.tftest.hcl` — apply-mode integration checks for real cluster validation

- `tests/basic.tftest.hcl` — core resources, secure defaults, prod/IRSA preconditions
- `tests/hpa.tftest.hcl` — HPA defaults and override behavior
- `tests/ingress.tftest.hcl` — ingress behavior, prometheus annotations, external secret mode

Run from the module directory:

```bash
terraform init -backend=false
terraform validate
terraform test
```

---

## Security Best Practices

### 1. Never hardcode secrets in `.tf` files

```hcl
# BAD
secret_data = { DB_PASSWORD = "hunter2" }

# GOOD — pull from Vault, SSM, or a tfvars file excluded from VCS
secret_data = { DB_PASSWORD = var.db_password }
```

### 2. Use IRSA instead of node-level IAM roles

IRSA scopes AWS permissions to a single pod. Without it, every pod on the
node inherits the node role — blast radius of a compromise is the entire node.

Also enforce role binding correctness: if `enable_irsa = true`, set a valid
`iam_role_arn` so the deployment fails fast at plan time instead of silently
running without intended AWS access.

### 3. Always set resource requests AND limits

The `resources` variable has no default on purpose. Unbounded pods risk noisy-neighbor
issues and node OOM kills. Limits also feed the HPA's utilization math.

### 4. Enable probes in every environment

Readiness probes prevent traffic hitting pods that aren't ready. Liveness probes
restart stuck processes. This module enforces probes in `prod`.

### 5. Keep pods evictable but protected

Enable PDB (`enable_pdb = true`) so voluntary disruptions (drain, upgrades) do
not take the service fully offline.

### 6. Restrict Ingress to known CIDR blocks (prod)

Use `ingress_annotations` to add WAF or security-group rules:

```hcl
ingress_annotations = {
  "alb.ingress.kubernetes.io/inbound-cidrs" = "10.0.0.0/8"
}
```

### 7. Mark sensitive outputs

The module marks `secret_data` as `sensitive = true`. If you pass secrets through
outputs, mark those outputs sensitive too.

### 8. Prefer external secret managers at scale

For production fleets, prefer `external_secret_name` (ESO / CSI) over
Terraform-managed `secret_data` to reduce secret value exposure in state.

### 9. Pin image tags — never use `latest`

`latest` is not reproducible and breaks rollback. Use immutable tags or digests.

---

## Anti-Patterns to Avoid

### ❌ Sharing one namespace across unrelated services

Each service (or bounded context) should have its own namespace for RBAC isolation
and resource quota scoping.

### ❌ Putting provider configuration in this module

Provider blocks belong in the **root** module only. Child modules declare
`required_providers` but never configure them.

### ❌ Using `lifecycle { ignore_changes }` on everything

`ignore_changes` hides drift. The only case here is replica count when HPA owns it —
handled by setting `replicas = null` so the field is simply omitted.

### ❌ One mega-module that creates the EKS cluster AND deploys services

Separate concerns: one module for cluster infrastructure, another (this one) for
workloads. They have different blast radii and change frequencies.

### ❌ Duplicating this module per environment

Use the **same module** with different variable values per environment. Directory
isolation (`environments/dev/`, `environments/prod/`) is for state separation,
not code duplication.

### ❌ Skipping variable validation

Without `validation {}` blocks, bad input surfaces as cryptic Kubernetes API errors
at apply time. Catch it early in the plan.

### ❌ Default resource requests / limits

Defaults like `cpu = "100m"` feel convenient but guarantee every service is mis-sized.
Force callers to measure and declare — that's why `resources` has no default.

### ❌ Storing Terraform state locally

Remote backend (S3 + DynamoDB, Terraform Cloud, etc.) with encryption and locking
is mandatory for team workflows and CI/CD. Not part of this module — configure it
in the root module's `backend.tf`.
