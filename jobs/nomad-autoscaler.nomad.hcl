job "nomad-autoscaler" {
  datacenters = ["dc1"]
  type        = "service"

  # Remove Consul dependency - run on any available node
  constraint {
    attribute = "${node.class}"
    operator  = "!="
    value     = "gpu-only"
  }

  group "autoscaler" {
    count = 1

    network {
      port "http" {
        to = 8080
      }
    }

    service {
      name = "nomad-autoscaler"
      port = "http"
      provider = "nomad"
      
      check {
        type     = "http"
        path     = "/v1/health"
        interval = "10s"
        timeout  = "3s"
      }
    }

    task "autoscaler" {
      driver = "docker"

      config {
        image = "hashicorp/nomad-autoscaler:0.3.7"
        ports = ["http"]

        command = "nomad-autoscaler"
        args = [
          "agent",
          "-config",
          "${NOMAD_TASK_DIR}/autoscaler.hcl",
          "-http-bind-address",
          "0.0.0.0"
        ]
      }

      template {
        destination = "${NOMAD_TASK_DIR}/autoscaler.hcl"
        change_mode = "restart"
        data = <<EOH
# Nomad Autoscaler Configuration
log_level = "DEBUG"
plugin_dir = "/plugins"

nomad {
  # Use template to get the host's IP, not localhost.
  address = "http://{{env "attr.unique.network.ip-address"}}:4646"
  namespace = "*"
}

# Prometheus APM plugin for WhisperLive metrics
apm "prometheus" {
  driver = "prometheus"
  config = {
    # Use Nomad service discovery to find Prometheus
{{ with nomadService "prometheus" }}{{ with index . 0 }}    address = "http://{{ .Address }}:{{ .Port }}"{{ end }}{{ end }}
  }
}

# Register the threshold strategy plugin
strategy "threshold" {
  driver = "threshold"
}

# Register the nomad task group target plugin
target "nomad" {
  driver = "nomad-target"
}

policy_eval {
  workers = {
    # Only enable horizontal scaling workers
    cluster    = 0
    horizontal = 4
    vertical   = 0  # Disable DAS (Dynamic Application Sizing)
  }
}

telemetry {
  prometheus_metrics = true
}
EOH
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
} 