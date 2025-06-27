job "bot-manager" {
  datacenters = ["dc1"]
  type        = "service"

  group "bot-manager" {
    count = 1
    
    # Use proper bridge networking with rootful Nomad
    network {
      mode = "bridge"
      port "http" {
        to     = 8080
        static = 8080
      }
    }

    # Service registration with Nomad
    service {
      provider = "nomad"
      name     = "bot-manager"
      port     = "http"
      address_mode = "host"
      
      check {
        type     = "http"
        path     = "/"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "bot-manager" {
      driver = "docker"
      
      config {
        image = "vexaai/bot-manager:dev"
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

      # Template for database connection using Nomad Variables
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

      # Resources for bot-manager (CPU intensive for orchestration)
      resources {
        cpu    = 500  # MHz - orchestration tasks
        memory = 512  # MB - moderate memory for FastAPI + async tasks
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