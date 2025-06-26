# Instance template for management servers (Nomad/Consul)
resource "google_compute_instance_template" "management" {
  name_prefix  = "management-template-"
  machine_type = "e2-medium"
  region       = var.gcp_region

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
}
