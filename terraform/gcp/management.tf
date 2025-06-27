# Startup script for management servers
locals {
  management_startup_script = file("${path.module}/scripts/nomad-server-with-discovery.sh")
}

# Instance template for management servers (Nomad/Consul)
resource "google_compute_instance_template" "management" {
  name_prefix  = "management-template-"
  machine_type = "e2-medium"
  region       = var.gcp_region
  
  tags = ["management", "nomad-server"]

  disk {
    source_image = "debian-cloud/debian-11"
    auto_delete  = true
    boot         = true
  }

  network_interface {
    subnetwork = google_compute_subnetwork.management.id
    access_config {
      // Ephemeral public IP
    }
  }

  service_account {
    scopes = ["cloud-platform"]
  }
  
  metadata_startup_script = local.management_startup_script

  lifecycle {
    create_before_destroy = true
  }
}

# Instance group for management servers
resource "google_compute_instance_group_manager" "management" {
  name               = "management-igm"
  base_instance_name = "management-server"
  zone               = "${var.gcp_region}-b" # Pinned to a single zone for simplicity for now
  target_size        = 3

  version {
    instance_template = google_compute_instance_template.management.id
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.management.id
    initial_delay_sec = 300
  }
}

# Health check for management servers
resource "google_compute_health_check" "management" {
  name               = "management-health-check"
  check_interval_sec = 30
  timeout_sec        = 10

  tcp_health_check {
    port = "4646" # Nomad server port
  }
}
