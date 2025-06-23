job "transcription-collector" {
  datacenters = ["dc1"]
  type        = "service"

  group "collector" {
    count = 1

    network {
      mode = "bridge"
      port "http" {
        to = 8000
      }
    }

    service {
      name = "transcription-collector"
      port = "http"
      provider = "nomad"

      check {
        type     = "http"
        path     = "/health"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "collector" {
      driver = "docker"

      config {
        image = "vexaai/transcription-collector:dev"
        ports = ["http"]
        force_pull = false

        # Mount alembic configuration files
        volumes = [
          "local/alembic.ini:/app/alembic.ini",
          "local/alembic:/app/alembic"
        ]
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

      # Database configuration template
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

      # Redis configuration template
      template {
        data = <<EOH
{{ with nomadService "redis" }}{{ with index . 0 }}REDIS_HOST={{ .Address }}
REDIS_PORT={{ .Port }}{{ end }}{{ end }}
REDIS_STREAM_NAME=transcription_segments
REDIS_CONSUMER_GROUP=collector_group
REDIS_STREAM_READ_COUNT=10
REDIS_STREAM_BLOCK_MS=2000
BACKGROUND_TASK_INTERVAL=10
IMMUTABILITY_THRESHOLD=30
REDIS_SEGMENT_TTL=3600
REDIS_CLEANUP_THRESHOLD=86400
LOG_LEVEL=DEBUG
EOH
        destination = "local/redis.env"
        env         = true
        splay       = "5s"
      }

      # Copy alembic configuration
      template {
        data = <<EOH
[alembic]
script_location = alembic
sqlalchemy.url = postgresql://postgres:postgres@172.17.0.1:25432/vexa

[post_write_hooks]

[loggers]
keys = root,sqlalchemy,alembic

[handlers]
keys = console

[formatters]
keys = generic

[logger_root]
level = WARN
handlers = console
qualname =

[logger_sqlalchemy]
level = WARN
handlers =
qualname = sqlalchemy.engine

[logger_alembic]
level = INFO
handlers =
qualname = alembic

[handler_console]
class = StreamHandler
args = (sys.stderr,)
level = NOTSET
formatter = generic

[formatter_generic]
format = %(levelname)-5.5s [%(name)s] %(message)s
datefmt = %H:%M:%S
EOH
        destination = "local/alembic.ini"
        perms = "644"
      }

      resources {
        cpu    = 300  # MHz
        memory = 512  # MB
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