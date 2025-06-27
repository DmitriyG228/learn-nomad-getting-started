# Startup script for bot nodes
locals {
  bots_startup_script = replace(
    file("${path.module}/scripts/nomad-client-with-discovery.sh"),
    "NODE_CLASS_PLACEHOLDER",
    "bot"
  )
}

# Instance template for bot application plane (static MIG)
resource "google_compute_instance_template" "bots" {
  name_prefix  = "bots-template-"
  machine_type = "e2-medium"
  region       = var.gcp_region

  disk {
    source_image = "debian-cloud/debian-11"
    auto_delete  = true
    boot         = true
    disk_size_gb = 30
  }

  network_interface {
    subnetwork = google_compute_subnetwork.bots.id
    access_config {
      // Ephemeral public IP
    }
  }

  service_account {
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = local.bots_startup_script

  lifecycle {
    create_before_destroy = true
  }
}

# Static MIG for bot application plane (Phase 3.0 - 2 nodes)
resource "google_compute_instance_group_manager" "bots" {
  name               = "bots-igm"
  base_instance_name = "bot-server"
  zone               = "${var.gcp_region}-b"
  target_size        = 2

  version {
    instance_template = google_compute_instance_template.bots.id
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.bots.id
    initial_delay_sec = 300
  }
}

# Health check for bot nodes
resource "google_compute_health_check" "bots" {
  name               = "bots-health-check"
  check_interval_sec = 30
  timeout_sec        = 10

  tcp_health_check {
    port = "4646" # Nomad client port
  }
}
