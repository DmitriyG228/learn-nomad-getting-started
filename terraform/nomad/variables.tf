variable "admin_api_token" {
  description = "Secret admin API token for the admin-api service"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Password for the Cloud SQL postgres user"
  type        = string
  sensitive   = true
} 