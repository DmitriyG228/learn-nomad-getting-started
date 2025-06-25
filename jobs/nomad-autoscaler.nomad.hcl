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
        image = "hashicorp/nomad-autoscaler:0.4.0"
        ports = ["http"]

        command = "nomad-autoscaler"
        args = [
          "agent",
          "-config",
          "${NOMAD_TASK_DIR}/autoscaler.hcl",
          "-http-bind-address",
          "0.0.0.0",
          "-log-level",
          "DEBUG"
        ]
      }

      template {
        destination = "${NOMAD_TASK_DIR}/autoscaler.hcl"
        data = <<EOH
# Nomad Autoscaler Configuration
log_level = "DEBUG"

nomad {
  # Connect to local Nomad agent (portable across environments)
  address = "http://127.0.0.1:4646"
  namespace = "*"
}

# Prometheus APM plugin for WhisperLive metrics
apm "prometheus" {
  driver = "prometheus"
  config = {
    # Use Nomad service discovery to find Prometheus
{{ with nomadService "prometheus" }}{{ with index . 0 }}    address = "http://{{ .Address }}:{{ .Port }}"{{ end }}{{ else }}    # Fallback if Prometheus service not found
    address = "http://127.0.0.1:9091"{{ end }}
  }
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