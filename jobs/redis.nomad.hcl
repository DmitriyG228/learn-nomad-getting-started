job "redis" {
  datacenters = ["dc1"]
  type        = "service"

  group "redis-db" {
    count = 1

    network {
      port "db" {
        to = 6379
      }
    }

    # This block registers the Redis instance as a service in Consul,
    # making it discoverable by other jobs. The service will be named "redis".
    service {
      name = "redis"
      port = "db"

      # Health check to ensure the service is actually running.
      check {
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "redis" {
      driver = "docker"

      config {
        image = "redis:7-alpine"
        ports = ["db"]
      }

      resources {
        cpu    = 200 # MHz
        memory = 256 # MB
      }
    }
  }
} 