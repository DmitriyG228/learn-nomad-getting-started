job "redis" {
  datacenters = ["dc1"]
  type        = "service"

  group "redis-db" {
    count = 1

    network {
      mode = "bridge"
      port "db" {
        static = 6379
        to = 6379
      }
    }

    service {
      provider = "nomad"
      name     = "redis"
      port     = "db"
      address_mode = "host"

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

      restart {
        attempts = 3
        interval = "10m"
        delay    = "30s"
        mode     = "fail"
      }
    }
  }
} 