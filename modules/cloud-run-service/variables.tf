variable "project_id" { type = string }
variable "region" { type = string }

variable "service_name" {
  type        = string
  description = "Cloud Run service name."
}

variable "image" {
  type        = string
  description = "Container image (Artifact Registry)."
}

variable "service_account_email" {
  type        = string
  description = "Runtime service account the container runs as."
}

variable "container_port" {
  type        = number
  default     = 8080
  description = "Port the container listens on. Cloud Run injects PORT with this value."
}

variable "min_instances" {
  type    = number
  default = 0
}

variable "max_instances" {
  type    = number
  default = 3
}

variable "cpu" {
  type    = string
  default = "1"
}

variable "memory" {
  type    = string
  default = "512Mi"
}

variable "ingress" {
  type        = string
  default     = "INGRESS_TRAFFIC_ALL"
  description = "INGRESS_TRAFFIC_ALL | INGRESS_TRAFFIC_INTERNAL_ONLY | INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER."
}

variable "allow_public_invoke" {
  type        = bool
  default     = false
  description = "Grant allUsers roles/run.invoker (public). Use only when auth is enforced in-app."
}

# ── Optional Direct VPC egress ───────────────────────────────────────────────
variable "enable_vpc" {
  type    = bool
  default = false
}

variable "vpc_network" {
  type        = string
  default     = ""
  description = "VPC network resource path (projects/*/global/networks/*). Required if enable_vpc."
}

variable "subnetwork" {
  type        = string
  default     = ""
  description = "Subnet resource path (projects/*/regions/*/subnetworks/*). Required if enable_vpc."
}

variable "vpc_egress" {
  type        = string
  default     = "ALL_TRAFFIC"
  description = "ALL_TRAFFIC | PRIVATE_RANGES_ONLY."
}

# ── Env ──────────────────────────────────────────────────────────────────────
variable "env_vars" {
  type        = map(string)
  default     = {}
  description = "Plain (non-secret) environment variables."
}

variable "secret_env" {
  type        = map(string)
  default     = {}
  description = "Secret environment variables: ENV_NAME => Secret Manager secret id (uses :latest)."
}
