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
      name     = "nomad-autoscaler"
      port     = "http"
      provider = "nomad"

      check {
        type     = "http"
        path     = "/v1/health"
        interval = "10s"
        timeout  = "3s"
        
        check_restart {
          limit = 3
          grace = "30s"
        }
      }
    }

    task "autoscaler" {
      driver = "docker"

      config {
        image = "hashicorp/nomad-autoscaler:0.4.1"
        ports = ["http"]

        # Direct command execution, no shell wrapper
        command = "nomad-autoscaler"
        args = [
          "agent",
          "-config=/local/autoscaler.hcl",
          "-http-bind-address=0.0.0.0",
          "-http-bind-port=8080",
          "-log-level=DEBUG"
        ]
      }

      template {
        destination = "local/autoscaler.hcl"
        change_mode = "restart"
        data        = <<EOH
# Nomad Autoscaler Configuration
log_level = "DEBUG"
plugin_dir = "/plugins"

nomad {
  address = "http://{{env "attr.unique.network.ip-address"}}:4646"
  namespace = "*"
}

apm "prometheus" {
  driver = "prometheus"
  config = {
    address = "http://192.168.1.4:9091"
  }
}

strategy "threshold" {
  driver = "threshold"
}

# Register the nomad task group target plugin
target "nomad" {
  driver = "nomad-target"
}

telemetry {
  prometheus_metrics = true
  disable_hostname = true
}
EOH
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
} 