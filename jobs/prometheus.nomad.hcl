job "prometheus" {
  datacenters = ["dc1"]
  type        = "service"

  # Constraint to run on core services plane
  constraint {
    attribute = "${node.class}"
    value     = "core"
  }

  group "prometheus" {
    count = 1

    network {
      port "prometheus_ui" {
        static = 9091
        to = 9090
      }
    }

    service {
      name = "prometheus"
      port = "prometheus_ui"
      provider = "nomad"
      
      check {
        type     = "http"
        path     = "/-/healthy"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "prometheus" {
      driver = "docker"

      config {
        image = "prom/prometheus:latest"
        ports = ["prometheus_ui"]

        args = [
          "--config.file=/etc/prometheus/config/prometheus.yml",
          "--storage.tsdb.path=/prometheus",
          "--web.console.libraries=/usr/share/prometheus/console_libraries",
          "--web.console.templates=/usr/share/prometheus/consoles",
          "--web.enable-lifecycle",
        ]

        volumes = [
          "local/config:/etc/prometheus/config",
        ]
      }

      template {
        data = <<EOH
---
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  # Scrape Nomad metrics
  - job_name: 'nomad'
    metrics_path: '/v1/metrics'
    params:
      format: ['prometheus']
    static_configs:
      - targets: ['192.168.1.4:4646']

  # Scrape WhisperLive metrics from our custom exporter
  - job_name: 'whisperlive-metrics'
    scrape_interval: 2s
    static_configs:
      - targets: ['192.168.1.4:9105']
    metrics_path: '/metrics'
EOH

        change_mode   = "signal"
        change_signal = "SIGHUP"
        destination   = "local/config/prometheus.yml"
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
} 