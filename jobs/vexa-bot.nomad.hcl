job "vexa-bot" {
  datacenters = ["dc1"]
  type        = "batch"

  # This makes the job a template that can be dispatched with a unique
  # payload and metadata for each invocation. The bot-manager will be
  # responsible for dispatching this job.
  parameterized {
    payload       = "forbidden"
    meta_required = ["session_id"]
  }

  group "bot-instance" {
    # When a bot-manager dispatches this job, a new allocation of this
    # group will be created.
    count = 1

    network {
      mode = "bridge"
    }

    task "bot" {
      driver = "docker"

      config {
        image = "vexa-bot:dev" # As defined in the original docker-compose.yml
        # Note: For this to work, the "vexa-bot:dev" image must be present
        # on the local Docker daemon where the Nomad client is running.
      }

      # The vexa-bot container will need environment variables to connect to
      # other services like Redis and Postgres. These will be provided by
      # Nomad's service discovery.
      #
      # We assume the bot has been refactored (as part of Phase 1.5) to use
      # these environment variables.
      env {
        # This gets the session_id passed by the bot-manager when the job
        # was dispatched.
        BOT_SESSION_ID = "${NOMAD_META_session_id}"

        # These values depend on the service discovery configuration of other jobs.
        # We will create redis.nomad and a local postgres.nomad job later.
        # For now, we assume they will register services named "redis" and "postgres".
        REDIS_ADDR     = "redis.service.consul:6379"
        DATABASE_URL   = "postgres://postgres:postgres@postgres.service.consul:5432/vexa?sslmode=disable"
      }

      resources {
        cpu    = 256 # Starting with a sensible default, in MHz
        memory = 256 # in MB
      }
    }
  }
} 