variable "namespace" {
  description = "Kubernetes namespace name"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,62}$", var.namespace))
    error_message = "Namespace must be lowercase alphanumeric with hyphens, 2-63 chars, starting with a letter."
  }
}

variable "app_name" {
  description = "Application name used for resource naming"
  type        = string
}

variable "container_image" {
  description = "Container image (e.g. nginx:1.25)"
  type        = string

  validation {
    condition     = can(regex("^.+:.+$", var.container_image))
    error_message = "Container image must include a tag (e.g. myapp:v1.0)."
  }
}

variable "replicas" {
  description = "Desired number of deployment replicas"
  type        = number
  default     = 2

  validation {
    condition     = var.replicas >= 1 && var.replicas <= 50
    error_message = "Replicas must be between 1 and 50."
  }
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8080
}

variable "service_type" {
  description = "Kubernetes service type"
  type        = string
  default     = "ClusterIP"

  validation {
    condition     = contains(["ClusterIP", "LoadBalancer", "NodePort"], var.service_type)
    error_message = "Service type must be ClusterIP, LoadBalancer, or NodePort."
  }
}

variable "service_port" {
  description = "Port exposed by the Kubernetes Service"
  type        = number
  default     = 80
}

variable "cpu_request" {
  description = "CPU request (e.g. 100m)"
  type        = string
  default     = "100m"
}

variable "cpu_limit" {
  description = "CPU limit (e.g. 500m)"
  type        = string
  default     = "500m"
}

variable "memory_request" {
  description = "Memory request (e.g. 128Mi)"
  type        = string
  default     = "128Mi"
}

variable "memory_limit" {
  description = "Memory limit (e.g. 512Mi)"
  type        = string
  default     = "512Mi"
}

# --- HPA ---

variable "hpa_min_replicas" {
  description = "HPA minimum replicas"
  type        = number
  default     = 2
}

variable "hpa_max_replicas" {
  description = "HPA maximum replicas"
  type        = number
  default     = 10

  validation {
    condition     = var.hpa_max_replicas >= 1
    error_message = "HPA max replicas must be at least 1."
  }
}

variable "hpa_cpu_target" {
  description = "HPA target CPU utilization percentage"
  type        = number
  default     = 70

  validation {
    condition     = var.hpa_cpu_target > 0 && var.hpa_cpu_target <= 100
    error_message = "HPA CPU target must be between 1 and 100."
  }
}

# --- IRSA ---

variable "iam_role_arn" {
  description = "IAM role ARN for IRSA-enabled service account"
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::\\d{12}:role/.+$", var.iam_role_arn))
    error_message = "Must be a valid IAM role ARN."
  }
}

# --- Ingress (conditional) ---

variable "ingress_enabled" {
  description = "Whether to create an Ingress resource"
  type        = bool
  default     = false
}

variable "ingress_host" {
  description = "Hostname for the ingress rule"
  type        = string
  default     = ""
}

variable "ingress_path" {
  description = "Path for the ingress rule"
  type        = string
  default     = "/"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "common_labels" {
  description = "Labels applied to all resources"
  type        = map(string)
  default     = {}
}
