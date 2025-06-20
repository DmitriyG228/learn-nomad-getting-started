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
        image = "services/admin-api:dev" # Using 'dev' tag instead of 'latest' to avoid forced pulls
        ports = ["http"]
        force_pull = false  # Use local image, don't try to pull from registry
      }

      # This template block dynamically creates a .env file inside the container.
      # It fetches the addresses of the redis and postgres services from Consul.
      template {
        data = <<EOH
DB_HOST=172.17.0.1
DB_PORT=25432
DB_NAME=vexa
DB_USER=postgres
DB_PASSWORD=postgres
REDIS_HOST={{ with service "redis" }}{{ with index . 0 }}{{ .Address }}{{ end }}{{ else }}172.17.0.1{{ end }}
REDIS_PORT={{ with service "redis" }}{{ with index . 0 }}{{ .Port }}{{ end }}{{ else }}31008{{ end }}
LOG_LEVEL=DEBUG
ADMIN_API_TOKEN=your-super-secret-token
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