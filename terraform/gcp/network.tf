# Main VPC for Vexa's GCP infrastructure
resource "google_compute_network" "main" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
  mtu                     = 1460
}

# Subnet for management instances (Nomad/Consul servers)
resource "google_compute_subnetwork" "management" {
  name          = "management-subnet"
  ip_cidr_range = var.management_subnet_cidr
  region        = var.gcp_region
  network       = google_compute_network.main.id
}

# Subnet for bot instances (MIG)
resource "google_compute_subnetwork" "bots" {
  name          = "bots-subnet"
  ip_cidr_range = var.bots_subnet_cidr
  region        = var.gcp_region
  network       = google_compute_network.main.id
}

# Subnet for core services instances (admin-api, redis, etc.)
resource "google_compute_subnetwork" "core" {
  name          = "core-subnet"
  ip_cidr_range = var.core_subnet_cidr
  region        = var.gcp_region
  network       = google_compute_network.main.id
}

# Firewall rule to allow internal traffic within the VPC
resource "google_compute_firewall" "allow-internal" {
  name    = "${var.vpc_name}-allow-internal"
  network = google_compute_network.main.name
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }
  source_ranges = ["10.0.0.0/8"] # Adjust if your internal ranges are different
}

# Firewall rule to allow SSH from anywhere
resource "google_compute_firewall" "allow-ssh" {
  name    = "${var.vpc_name}-allow-ssh"
  network = google_compute_network.main.name
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["0.0.0.0/0"]
}

# Firewall rule to allow Nomad and Consul communication
resource "google_compute_firewall" "allow-nomad-consul" {
  name    = "${var.vpc_name}-allow-nomad-consul"
  network = google_compute_network.main.name
  
  allow {
    protocol = "tcp"
    ports    = [
      "4646", # Nomad HTTP
      "4647", # Nomad RPC
      "4648", # Nomad Serf
      "8300", # Consul server RPC
      "8301", # Consul LAN Serf
      "8302", # Consul WAN Serf
      "8500", # Consul HTTP
      "8502", # Consul gRPC
      "8600"  # Consul DNS
    ]
  }
  
  allow {
    protocol = "udp"
    ports    = [
      "4648", # Nomad Serf
      "8301", # Consul LAN Serf
      "8302", # Consul WAN Serf
      "8600"  # Consul DNS
    ]
  }
  
  source_ranges = ["10.0.0.0/8"]
}

# Firewall rule to allow web UIs from anywhere (optional for demo)
resource "google_compute_firewall" "allow-web-ui" {
  name    = "${var.vpc_name}-allow-web-ui"
  network = google_compute_network.main.name
  
  allow {
    protocol = "tcp"
    ports    = [
      "4646", # Nomad UI
      "8500"  # Consul UI
    ]
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["management"]
}
