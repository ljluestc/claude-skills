# ─────────────────────────────────────────────────────────────────────
# Core
# ─────────────────────────────────────────────────────────────────────

variable "name" {
  description = "Service name — used for all Kubernetes resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.name))
    error_message = "Must be a valid DNS label: lowercase, start with letter, max 63 chars."
  }
}

variable "namespace" {
  description = "Kubernetes namespace to deploy into."
  type        = string
}

variable "create_namespace" {
  description = "Whether to create the namespace. Set false when the namespace already exists."
  type        = bool
  default     = true
}

variable "environment" {
  description = "Target environment. Drives default replica counts and HPA bounds."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Must be dev, staging, or prod."
  }
}

variable "labels" {
  description = "Additional labels merged onto every resource."
  type        = map(string)
  default     = {}
}

variable "pod_annotations" {
  description = "Annotations applied to pod template metadata."
  type        = map(string)
  default     = {}
}

# ─────────────────────────────────────────────────────────────────────
# Container
# ─────────────────────────────────────────────────────────────────────

variable "image" {
  description = "Container image repository (without tag)."
  type        = string
}

variable "image_tag" {
  description = "Container image tag."
  type        = string
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 8080
}

variable "command" {
  description = "Override the container entrypoint."
  type        = list(string)
  default     = null
}

variable "args" {
  description = "Arguments passed to the container entrypoint."
  type        = list(string)
  default     = null
}

# ─────────────────────────────────────────────────────────────────────
# Resources — intentionally no default; must be explicit.
# ─────────────────────────────────────────────────────────────────────

variable "resources" {
  description = "CPU and memory requests/limits. No default — forces explicit sizing."
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
}

variable "replicas" {
  description = "Replica count. Null = use environment default (dev:1, staging:2, prod:3)."
  type        = number
  default     = null
}

# ─────────────────────────────────────────────────────────────────────
# Probes
# ─────────────────────────────────────────────────────────────────────

variable "readiness_probe" {
  description = "HTTP readiness probe configuration. Null disables the probe."
  type = object({
    path                  = string
    port                  = optional(number)
    initial_delay_seconds = optional(number, 10)
    period_seconds        = optional(number, 10)
    timeout_seconds       = optional(number, 5)
    failure_threshold     = optional(number, 3)
  })
  default = null
}

variable "liveness_probe" {
  description = "HTTP liveness probe configuration. Null disables the probe."
  type = object({
    path                  = string
    port                  = optional(number)
    initial_delay_seconds = optional(number, 15)
    period_seconds        = optional(number, 20)
    timeout_seconds       = optional(number, 5)
    failure_threshold     = optional(number, 3)
  })
  default = null
}

# ─────────────────────────────────────────────────────────────────────
# Environment variables / config
# ─────────────────────────────────────────────────────────────────────

variable "env_vars" {
  description = "Direct environment variables injected into the container."
  type        = map(string)
  default     = {}
}

variable "config_data" {
  description = "Data for a ConfigMap. All keys are injected as env vars. Empty = no ConfigMap."
  type        = map(string)
  default     = {}
}

variable "secret_data" {
  description = "Data for an Opaque Secret. All keys injected as env vars. Empty = no Secret."
  type        = map(string)
  default     = {}
  sensitive   = true
}

# ─────────────────────────────────────────────────────────────────────
# Service
# ─────────────────────────────────────────────────────────────────────

variable "service_type" {
  description = "Kubernetes Service type."
  type        = string
  default     = "ClusterIP"

  validation {
    condition     = contains(["ClusterIP", "NodePort", "LoadBalancer"], var.service_type)
    error_message = "Must be ClusterIP, NodePort, or LoadBalancer."
  }
}

variable "service_port" {
  description = "Port exposed by the Service."
  type        = number
  default     = 80
}

# ─────────────────────────────────────────────────────────────────────
# HPA
# ─────────────────────────────────────────────────────────────────────

variable "enable_hpa" {
  description = "Enable HorizontalPodAutoscaler."
  type        = bool
  default     = false
}

variable "hpa_min_replicas" {
  description = "HPA minimum replicas. Null = use environment default."
  type        = number
  default     = null
}

variable "hpa_max_replicas" {
  description = "HPA maximum replicas. Null = use environment default."
  type        = number
  default     = null
}

variable "hpa_cpu_target" {
  description = "Target average CPU utilization percentage for HPA scaling."
  type        = number
  default     = 75
}

variable "hpa_memory_target" {
  description = "Target average memory utilization percentage. Null disables memory metric."
  type        = number
  default     = null
}

variable "hpa_scale_up_stabilization" {
  description = "Seconds to wait after a scale-up before allowing another. Prevents flapping."
  type        = number
  default     = 60
}

variable "hpa_scale_down_stabilization" {
  description = "Seconds to wait after a scale-down before allowing another. Prevents thrashing."
  type        = number
  default     = 300
}

# ─────────────────────────────────────────────────────────────────────
# IRSA (IAM Roles for Service Accounts)
# ─────────────────────────────────────────────────────────────────────

variable "enable_irsa" {
  description = "Create a Kubernetes ServiceAccount annotated for IRSA."
  type        = bool
  default     = false
}

variable "iam_role_arn" {
  description = "IAM role ARN to associate with the service account. Required when enable_irsa = true."
  type        = string
  default     = ""

  validation {
    condition     = var.iam_role_arn == "" || can(regex("^arn:aws:iam::\\d{12}:role/.+$", var.iam_role_arn))
    error_message = "Must be a valid IAM role ARN or empty string."
  }
}

# ─────────────────────────────────────────────────────────────────────
# Ingress (optional)
# ─────────────────────────────────────────────────────────────────────

variable "enable_ingress" {
  description = "Create a Kubernetes Ingress resource."
  type        = bool
  default     = false
}

variable "ingress_class" {
  description = "Ingress class name (e.g. alb, nginx)."
  type        = string
  default     = "alb"
}

variable "ingress_host" {
  description = "Hostname for the Ingress rule."
  type        = string
  default     = ""
}

variable "ingress_path" {
  description = "Path prefix for the Ingress rule."
  type        = string
  default     = "/"
}

variable "ingress_path_type" {
  description = "Ingress path match type."
  type        = string
  default     = "Prefix"

  validation {
    condition     = contains(["Prefix", "Exact", "ImplementationSpecific"], var.ingress_path_type)
    error_message = "Must be Prefix, Exact, or ImplementationSpecific."
  }
}

variable "ingress_annotations" {
  description = "Additional annotations for the Ingress resource."
  type        = map(string)
  default     = {}
}

variable "ingress_tls_secret" {
  description = "Name of the TLS Secret for HTTPS. Null = no TLS termination."
  type        = string
  default     = null
}

# ─────────────────────────────────────────────────────────────────────
# PodDisruptionBudget
# ─────────────────────────────────────────────────────────────────────

variable "enable_pdb" {
  description = "Create a PodDisruptionBudget for the Deployment."
  type        = bool
  default     = true
}

variable "pdb_min_available" {
  description = "Minimum available pods during voluntary disruptions (absolute or %)."
  type        = string
  default     = "50%"
}

# ─────────────────────────────────────────────────────────────────────
# Security Context — secure by default
# ─────────────────────────────────────────────────────────────────────

variable "security_context" {
  description = "Pod-level security context. Secure defaults applied when left empty."
  type = object({
    run_as_non_root = optional(bool, true)
    run_as_user     = optional(number, 1000)
    run_as_group    = optional(number, 1000)
    fs_group        = optional(number, 1000)
  })
  default = {}
}

variable "container_security_context" {
  description = "Container-level security context. Secure defaults applied when left empty."
  type = object({
    allow_privilege_escalation = optional(bool, false)
    read_only_root_filesystem  = optional(bool, true)
    run_as_non_root            = optional(bool, true)
  })
  default = {}
}

# ─────────────────────────────────────────────────────────────────────
# Rollout Strategy
# ─────────────────────────────────────────────────────────────────────

variable "rollout_strategy" {
  description = "Deployment rollout strategy. Default ensures zero-downtime deploys."
  type = object({
    type            = optional(string, "RollingUpdate")
    max_surge       = optional(string, "25%")
    max_unavailable = optional(string, "0")
  })
  default = {}
}

# ─────────────────────────────────────────────────────────────────────
# Pod Anti-Affinity
# ─────────────────────────────────────────────────────────────────────

variable "enable_pod_anti_affinity" {
  description = "Spread pods across nodes via preferred anti-affinity on hostname."
  type        = bool
  default     = true
}

# ─────────────────────────────────────────────────────────────────────
# Prometheus Annotations
# ─────────────────────────────────────────────────────────────────────

variable "enable_prometheus" {
  description = "Add Prometheus scraping annotations to pods."
  type        = bool
  default     = false
}

variable "prometheus_port" {
  description = "Port Prometheus should scrape. Defaults to container_port."
  type        = number
  default     = null
}

variable "prometheus_path" {
  description = "Path Prometheus should scrape."
  type        = string
  default     = "/metrics"
}

# ─────────────────────────────────────────────────────────────────────
# External Secrets
# ─────────────────────────────────────────────────────────────────────

variable "external_secret_name" {
  description = "Name of a pre-existing Secret (e.g. from External Secrets Operator). Takes precedence over secret_data."
  type        = string
  default     = null
}
