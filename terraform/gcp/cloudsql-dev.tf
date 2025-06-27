# Cloud SQL (PostgreSQL) DEV instance for Vexa
# Follows best-practice: instance lifecycle managed by Terraform; schema managed separately by Alembic migrations.

# Enable required service APIs once per project (safe to run multiple times)
resource "google_project_service" "sqladmin" {
  service = "sqladmin.googleapis.com"
}

# Random strong password for the postgres user (stored in Secret Manager)
resource "random_password" "db_pass" {
  length  = 32
  special = true
}

# Secret Manager secret holding the DB password
resource "google_secret_manager_secret" "db_pass" {
  secret_id = "vexa-dev-db-password"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_pass_ver" {
  secret      = google_secret_manager_secret.db_pass.id
  secret_data = random_password.db_pass.result
}

# Private IP range for Cloud SQL (one-time) – uses a /24 in 10.0.4.0/24
resource "google_compute_global_address" "cloudsql_private_range" {
  name          = "cloudsql-dev-private-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 24
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "cloudsql_vpc_connection" {
  network = google_compute_network.main.id
  service = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.cloudsql_private_range.name]
}

# Cloud SQL instance (PostgreSQL 15)
resource "google_sql_database_instance" "dev" {
  name             = "vexa-dev-postgres"
  database_version = "POSTGRES_15"
  region           = var.gcp_region

  settings {
    tier = "db-custom-1-3840" # 1 vCPU / 3.75 GB RAM

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.main.self_link
    }
  }

  deletion_protection = false # dev only
  depends_on = [google_service_networking_connection.cloudsql_vpc_connection]
}

# Default database
resource "google_sql_database" "vexa" {
  name     = "vexa"
  instance = google_sql_database_instance.dev.name
  charset  = "UTF8"
  collation = "en_US.UTF8"
}

# Postgres user (matches local dev credentials)
resource "google_sql_user" "postgres" {
  name     = "postgres"
  instance = google_sql_database_instance.dev.name
  password = random_password.db_pass.result
}

# Output useful connection info
output "dev_db_private_ip" {
  value = google_sql_database_instance.dev.private_ip_address
} 