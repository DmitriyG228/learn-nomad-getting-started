# Startup script for core services nodes
locals {
  core_startup_script = replace(
    file("${path.module}/scripts/nomad-client-with-discovery.sh"),
    "NODE_CLASS_PLACEHOLDER",
    "core"
  )
}

# Instance template for core services (admin-api, redis, bot-manager, etc.)
resource "google_compute_instance_template" "core" {
  name_prefix  = "core-template-"
  machine_type = "e2-small"
  region       = var.gcp_region

  disk {
    source_image = "debian-cloud/debian-11"
    auto_delete  = true
    boot         = true
    disk_size_gb = 20
  }

  network_interface {
    subnetwork = google_compute_subnetwork.core.id
    access_config {
      // Ephemeral public IP
    }
  }

  service_account {
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = local.core_startup_script

  lifecycle {
    create_before_destroy = true
  }
}

# Instance group for core services
resource "google_compute_instance_group_manager" "core" {
  name               = "core-igm"
  base_instance_name = "core-server"
  zone               = "${var.gcp_region}-b"
  target_size        = 2

  version {
    instance_template = google_compute_instance_template.core.id
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.core.id
    initial_delay_sec = 300
  }
}

# Health check for core services
resource "google_compute_health_check" "core" {
  name               = "core-health-check"
  check_interval_sec = 30
  timeout_sec        = 10

  tcp_health_check {
    port = "4646" # Nomad client port
  }
} 