# -----------------------------------------------------------------------------
#  Load-balancers for stable public endpoints
# -----------------------------------------------------------------------------
#  We expose two services:
#   1. API-Gateway  – port 8926 – points to all core-MIG instances
#   2. Nomad API/UI – port 4646 – points to all management-MIG instances
#
#  Pattern: Regional external TCP LB (Network Load Balancer v1)
#           Static regional IP  →  Forwarding Rule  →  Backend Service  →  MIG
# -----------------------------------------------------------------------------

###############################################################################
# API-Gateway (core MIG)                                                      #
###############################################################################

resource "google_compute_address" "api_gw" {
  name   = "${var.vpc_name}-api-gw-ip"
  region = var.gcp_region
}

resource "google_compute_region_health_check" "api_gw" {
  name               = "${var.vpc_name}-api-gw-hc"
  region             = var.gcp_region
  tcp_health_check { port = 8926 }
  check_interval_sec = 10
  timeout_sec        = 5
}

resource "google_compute_region_backend_service" "api_gw" {
  name                  = "${var.vpc_name}-api-gw-bs"
  protocol              = "TCP"
  region                = var.gcp_region
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_region_health_check.api_gw.self_link]

  backend {
    group          = google_compute_instance_group_manager.core.instance_group
    balancing_mode = "CONNECTION"
  }
}

resource "google_compute_forwarding_rule" "api_gw" {
  name                  = "${var.vpc_name}-api-gw-fr"
  region                = var.gcp_region
  load_balancing_scheme = "EXTERNAL"
  ip_protocol           = "TCP"
  port_range            = "8926"
  ip_address            = google_compute_address.api_gw.address
  backend_service       = google_compute_region_backend_service.api_gw.self_link
}

###############################################################################
# Nomad servers (management MIG)                                             #
###############################################################################

resource "google_compute_address" "nomad_lb" {
  name   = "${var.vpc_name}-nomad-ip"
  region = var.gcp_region
}

resource "google_compute_region_health_check" "nomad" {
  name               = "${var.vpc_name}-nomad-hc"
  region             = var.gcp_region
  tcp_health_check { port = 4646 }
  check_interval_sec = 10
  timeout_sec        = 5
}

resource "google_compute_region_backend_service" "nomad" {
  name                  = "${var.vpc_name}-nomad-bs"
  protocol              = "TCP"
  region                = var.gcp_region
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_region_health_check.nomad.self_link]

  backend {
    group          = google_compute_instance_group_manager.management.instance_group
    balancing_mode = "CONNECTION"
  }
}

resource "google_compute_forwarding_rule" "nomad" {
  name                  = "${var.vpc_name}-nomad-fr"
  region                = var.gcp_region
  load_balancing_scheme = "EXTERNAL"
  ip_protocol           = "TCP"
  port_range            = "4646"
  ip_address            = google_compute_address.nomad_lb.address
  backend_service       = google_compute_region_backend_service.nomad.self_link
}

###############################################################################
# Outputs                                                                    #
###############################################################################

output "api_gateway_public_ip" {
  description = "Static external IP for the API Gateway"
  value       = google_compute_address.api_gw.address
}

output "nomad_public_ip" {
  description = "Static external IP for Nomad servers (UI & API)"
  value       = google_compute_address.nomad_lb.address
} 