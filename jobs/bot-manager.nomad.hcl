job "bot-manager" {
  datacenters = ["dc1"]
  type        = "service"

  group "bot-manager" {
    count = 1
    
    # Use proper bridge networking with rootful Nomad
    network {
      mode = "bridge"
      port "http" {
        to = 8080
      }
    }

    task "bot-manager" {
      driver = "docker"
      
      config {
        image = "services/bot-manager:dev"
        ports = ["http"]
        force_pull = false  # Use local image, don't try to pull from registry
        # Use container default port (8080) with bridge networking
      }

      # Environment variables for bot-manager to work with Nomad
      env {
        ORCHESTRATOR = "nomad"
        LOG_LEVEL = "DEBUG"
      }

      # Wait for dependencies to be available
      template {
        data = <<EOH
# This template ensures Redis and Postgres services are available
{{ with nomadService "redis" }}{{ with index . 0 }}# Redis available at {{ .Address }}:{{ .Port }}{{ end }}{{ end }}
# We are using external postgres, so we don't check for it here
EOH
        destination = "local/dependencies"
        change_mode = "restart"
        perms = "644"
      }

      # Template for database connection (using external postgres service)
      template {
        data = <<EOH
# Fallback to external postgres (vexa-ext-postgres)
DB_HOST=172.17.0.1
DB_PORT=25432
DB_NAME=vexa
DB_USER=postgres
DB_PASSWORD=postgres
EOH
        destination = "local/db.env"
        env         = true
      }

      # Template for Redis connection using Nomad service discovery
      template {
        data = <<EOH
{{ with nomadService "redis" }}{{ with index . 0 }}REDIS_URL=redis://{{ .Address }}:{{ .Port }}/0{{ end }}{{ end }}
EOH
        destination = "local/redis.env"
        env         = true
      }

      # Template for Nomad API access from bridge network
      template {
        data = <<EOH
NOMAD_ADDR=http://{{ env "attr.unique.network.ip-address" }}:4646
EOH
        destination = "local/nomad.env"
        env         = true
      }

      # Resources for bot-manager (CPU intensive for orchestration)
      resources {
        cpu    = 500  # MHz - orchestration tasks
        memory = 512  # MB - moderate memory for FastAPI + async tasks
      }
      
      # Service registration with Consul
      service {
        provider = "nomad"
        name     = "bot-manager"
        port     = "http"
        
        check {
          type     = "http"
          path     = "/"
          interval = "30s"
          timeout  = "5s"
        }
      }

      # Restart policy for service jobs
      restart {
        attempts = 3
        interval = "10m"
        delay    = "30s"
        mode     = "fail"
      }
    }
  }
} 