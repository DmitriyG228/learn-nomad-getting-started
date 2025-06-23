job "admin-api" {
  datacenters = ["dc1"]
  type        = "service"

  group "api" {
    count = 1

    network {
      mode = "bridge"
      port "http" {
        to = 8001
      }
    }

    service {
      name = "admin-api"
      port = "http"
      provider = "nomad"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "server" {
      driver = "docker"

      config {
        image = "vexaai/admin-api:dev" # Using 'dev' tag instead of 'latest' to avoid forced pulls
        ports = ["http"]
        force_pull = false  # Use local image, don't try to pull from registry
      }

      # This template block dynamically creates a .env file inside the container.
      # It fetches the addresses of redis and postgres services from Consul.
      template {
        data = <<EOH
# Fallback to external postgres (vexa-ext-postgres)
DB_HOST=172.17.0.1
DB_PORT=25432
DB_NAME=vexa
DB_USER=postgres
DB_PASSWORD=postgres
{{ with nomadService "redis" }}{{ with index . 0 }}REDIS_HOST={{ .Address }}
REDIS_PORT={{ .Port }}{{ end }}{{ end }}
LOG_LEVEL=DEBUG
ADMIN_API_TOKEN=vexa-admin-secret-2025
EOH
        destination = "secrets/app.env"
        env         = true
      }

      resources {
        cpu    = 500 # MHz
        memory = 256 # MB
      }
    }
  }
} 