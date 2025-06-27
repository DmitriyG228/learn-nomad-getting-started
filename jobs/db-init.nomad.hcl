job "db-init" {
  datacenters = ["dc1"]
  type        = "batch"

  constraint {
    attribute = "${node.class}"
    value     = "core"
  }

  group "init" {
    count = 1

    task "init-schema" {
      driver = "docker"

      config {
        image   = "vexaai/transcription-collector:dev"
        command = "python"
        args    = ["-c", "import asyncio; from shared_models.database import init_db; asyncio.run(init_db())"]
      }

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
        destination = "secrets/db.env"
        env         = true
      }

      resources {
        cpu    = 200
        memory = 256
      }
      
      restart {
        attempts = 1
        delay = "15s"
        mode = "fail"
      }
    }
  }
} 