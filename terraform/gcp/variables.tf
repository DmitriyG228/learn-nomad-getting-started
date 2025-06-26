variable "gcp_project_id" {
  description = "The GCP project ID to deploy resources into."
  type        = string
}

variable "gcp_region" {
  description = "The GCP region to deploy resources into."
  type        = string
  default     = "us-central1"
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
