variable "VULTR_API_KEY" {
  description = "Vultr API key for authentication"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Vultr region to deploy resources"
  type        = string
  default     = "ewr"  # New Jersey - good for US/EU connectivity
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "vexa"
}

variable "environment" {
  description = "Environment name (prod, staging, dev)"
  type        = string
  default     = "prod"
}

# Nomad Server Configuration
variable "nomad_server_count" {
  description = "Number of Nomad server nodes (must be odd for quorum)"
  type        = number
  default     = 3
}

variable "nomad_server_plan" {
  description = "Vultr plan for Nomad server nodes"
  type        = string
  default     = "vhp-4c-8gb"  # High Performance: 4 vCPU, 8GB RAM, 180GB Storage
}

# Nomad Client Configuration - Static Services
variable "nomad_client_static_count" {
  description = "Number of Nomad client nodes for static services"
  type        = number
  default     = 2
}

variable "nomad_client_static_plan" {
  description = "Vultr plan for static service client nodes"
  type        = string
  default     = "vhp-4c-8gb"  # High Performance: 4 vCPU, 8GB RAM, 180GB Storage
}

# Nomad Client Configuration - Scalable Workloads
variable "nomad_client_workload_count" {
  description = "Number of Nomad client nodes for scalable workloads"
  type        = number
  default     = 3
}

variable "nomad_client_workload_plan" {
  description = "Vultr plan for workload client nodes"
  type        = string
  default     = "vhp-2c-4gb"  # High Performance: 2 vCPU, 4GB RAM, 100GB Storage
}

# GPU Node Configuration
variable "nomad_client_gpu_count" {
  description = "Number of GPU-enabled client nodes"
  type        = number
  default     = 1
}

variable "nomad_client_gpu_plan" {
  description = "Vultr plan for GPU client nodes"
  type        = string
  default     = "vcg-a16-2c-8g-50s-1gpu"  # NVIDIA A16 1/8: 2 vCPU, 8GB RAM, 50GB Storage, 2GB GPU
}

# Operating System
variable "os_id" {
  description = "Vultr OS ID (Ubuntu 22.04 LTS)"
  type        = string
  default     = "1743"  # Ubuntu 22.04 LTS x64
}

# SSH Configuration
variable "ssh_key_name" {
  description = "Name for the SSH key resource"
  type        = string
  default     = "vexa-deployment-key"
}

# Load Balancer Configuration
variable "load_balancer_size" {
  description = "Size of the load balancer"
  type        = string
  default     = "lb-small"
}

# Firewall Configuration
variable "allowed_ssh_cidr" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Restrict this in production
}

variable "allowed_http_cidr" {
  description = "CIDR blocks allowed for HTTP/HTTPS access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Nomad Configuration
variable "nomad_version" {
  description = "Version of Nomad to install"
  type        = string
  default     = "1.10.2"
}

variable "nomad_datacenter" {
  description = "Nomad datacenter name"
  type        = string
  default     = "dc1"
}

variable "nomad_region" {
  description = "Nomad region name"
  type        = string
  default     = "global"
}

# Docker Configuration
variable "docker_version" {
  description = "Version of Docker to install"
  type        = string
  default     = "latest"
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "vexa"
    Environment = "prod"
    ManagedBy   = "terraform"
  }
} 

# Database Configuration for Nomad Jobs
variable "db_host" {
  description = "External PostgreSQL database host"
  type        = string
  default     = "172.17.0.1"  # Default Docker host IP for external postgres
}

variable "db_port" {
  description = "External PostgreSQL database port"
  type        = string
  default     = "25432"  # Default external postgres port
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "vexa"
}

variable "db_user" {
  description = "PostgreSQL database user"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "PostgreSQL database password"
  type        = string
  sensitive   = true
  default     = "postgres"
}

variable "admin_api_token" {
  description = "Admin API authentication token"
  type        = string
  sensitive   = true
  default     = "vexa-admin-token-2024"
} 