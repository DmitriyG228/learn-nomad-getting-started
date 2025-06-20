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
        # Use container default port (8080) with bridge networking
      }

      # Environment variables for bot-manager to work with Nomad
      env {
        ORCHESTRATOR = "nomad"
        LOG_LEVEL = "DEBUG"
        DEVICE_TYPE = "cpu"
        NOMAD_ADDR = "http://172.17.0.1:4646"
      }

      # Template for database connection (using external postgres service)
      template {
        data = <<EOH
DB_HOST=172.17.0.1
DB_PORT=25432
DB_NAME=vexa
DB_USER=postgres
DB_PASSWORD=postgres
EOH
        destination = "local/db.env"
        env         = true
      }

      # Template for Redis connection (via Docker gateway from bridge network)
      template {
        data = <<EOH
REDIS_URL=redis://172.17.0.1:25600/0
EOH
        destination = "local/redis.env"
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