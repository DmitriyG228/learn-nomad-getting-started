variable "gcp_project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "The GCP region"
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "The GCP zone"
  type        = string
  default     = "us-central1-b"
}

variable "admin_api_token" {
  description = "The secret token for the Admin API"
  type        = string
  sensitive   = true
}

variable "core_subnet_cidr" {
  description = "The IP CIDR range for the core services subnet"
  type        = string
  default     = "10.0.3.0/24"
}

variable "vpc_name" {
  description = "The name of the VPC network."
  type        = string
  default     = "vexa-gcp-vpc"
}

variable "management_subnet_cidr" {
  description = "The IP CIDR range for the management subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "bots_subnet_cidr" {
  description = "The IP CIDR range for the bots subnet."
  type        = string
  default     = "10.0.2.0/24"
}

variable "db_password" {
  description = "Custom database password (optional - if not provided, will be auto-generated)"
  type        = string
  default     = null
  sensitive   = true
}
