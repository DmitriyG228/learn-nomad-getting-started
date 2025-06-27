job "api-gateway" {
  datacenters = ["dc1"]
  type        = "service"

  # Constraint to run on core services plane
  constraint {
    attribute = "${node.class}"
    value     = "core"
  }

  group "gateway" {
    count = 1

    network {
      mode = "bridge"
      port "http" {
        static = 8926  # Fixed port for stable access
        to = 8000
      }
    }

    service {
      name = "api-gateway"
      port = "http"
      provider = "nomad"
      address_mode = "alloc"

      check {
        type     = "http"
        path     = "/"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "gateway" {
      driver = "docker"

      config {
        image = "vexaai/api-gateway:dev"
        ports = ["http"]
        force_pull = false
      }

      # Wait for backend services to be available
      template {
        data = <<EOH
# This template ensures backend services are available
{{ with nomadService "admin-api" }}{{ with index . 0 }}# Admin API available at {{ .Address }}:{{ .Port }}{{ end }}{{ end }}
{{ with nomadService "bot-manager" }}{{ with index . 0 }}# Bot Manager available at {{ .Address }}:{{ .Port }}{{ end }}{{ end }}
{{ with nomadService "transcription-collector" }}{{ with index . 0 }}# Transcription Collector available at {{ .Address }}:{{ .Port }}{{ end }}{{ end }}
EOH
        destination = "local/dependencies"
        change_mode = "restart"
        perms = "644"
      }

      # Service URLs configuration
      template {
        data = <<EOH
{{ with nomadService "admin-api" }}{{ with index . 0 }}ADMIN_API_URL=http://{{ .Address }}:{{ .Port }}{{ end }}{{ end }}
{{ with nomadService "bot-manager" }}{{ with index . 0 }}BOT_MANAGER_URL=http://{{ .Address }}:{{ .Port }}{{ end }}{{ end }}
{{ with nomadService "transcription-collector" }}{{ with index . 0 }}TRANSCRIPTION_COLLECTOR_URL=http://{{ .Address }}:{{ .Port }}{{ end }}{{ end }}
LOG_LEVEL=DEBUG
EOH
        destination = "local/services.env"
        env         = true
      }

      resources {
        cpu    = 300  # MHz
        memory = 256  # MB
      }

      restart {
        attempts = 3
        interval = "10m"
        delay    = "30s"
        mode     = "fail"
      }
    }
  }
} 