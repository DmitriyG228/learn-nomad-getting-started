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
      address_mode = "alloc"

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
# Database configuration using Nomad Variables
{{ with nomadVar "secret/vexa/db" }}
DB_HOST={{ .host }}
DB_PORT={{ .port }}
DB_NAME={{ .name }}
DB_USER={{ .user }}
DB_PASSWORD={{ .password }}
{{ end }}
{{ with nomadService "redis" }}{{ with index . 0 }}REDIS_HOST={{ .Address }}
REDIS_PORT={{ .Port }}{{ end }}{{ end }}
LOG_LEVEL=DEBUG
{{ with nomadVar "secret/vexa/admin-api" }}
ADMIN_API_TOKEN={{ .token }}
{{ end }}
EOH
        destination = "secrets/app.env"
        env         = true
      }

      resources {
        cpu    = 500 # MHz
        memory = 256 # MB
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