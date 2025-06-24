job "whisperlive-cpu" {
  datacenters = ["dc1"]
  type        = "service"

  group "whisperlive-cpu" {
    count = 2  # Match docker-compose CPU replicas

    network {
      mode = "bridge"
      port "ws" {
        to = 9090
      }
      port "health" {
        to = 9091
      }
    }

    service {
      name = "whisperlive-cpu"
      port = "ws"
      provider = "nomad"
      address_mode = "alloc"

      check {
        type     = "http"
        port     = "health"
        path     = "/health"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "whisperlive-cpu-server" {
      driver = "docker"

      config {
        image = "vexaai/whisperlive:cpu-dev"
        ports = ["ws", "health"]
        force_pull = false

        # Mount model cache
        volumes = [
          "local/hub:/root/.cache/huggingface/hub",
          "local/models:/app/models"
        ]
      }

      # Wait for dependencies
      template {
        data = <<EOH
# This template ensures Redis and transcription-collector services are available
{{ with nomadService "redis" }}{{ with index . 0 }}# Redis available at {{ .Address }}:{{ .Port }}{{ end }}{{ end }}
{{ with nomadService "transcription-collector" }}{{ with index . 0 }}# Transcription collector available at {{ .Address }}:{{ .Port }}{{ end }}{{ end }}
EOH
        destination = "local/dependencies"
        change_mode = "restart"
        perms = "644"
      }

      # Environment configuration
      template {
        data = <<EOH
{{ with nomadService "redis" }}{{ with index . 0 }}REDIS_STREAM_URL=redis://{{ .Address }}:{{ .Port }}/0/transcription_segments
TRANSCRIPTION_COLLECTOR_URL=redis://{{ .Address }}:{{ .Port }}/0/transcription_segments
REDIS_URL=redis://{{ .Address }}:{{ .Port }}/0
REDIS_HOST={{ .Address }}
REDIS_PORT={{ .Port }}{{ end }}{{ end }}
REDIS_DB=0
REDIS_STREAM_NAME=transcription_segments
LANGUAGE_DETECTION_SEGMENTS=10
VAD_FILTER_THRESHOLD=0.5
DEVICE_TYPE=cpu
# Nomad-specific environment for URL registration
NOMAD_ALLOC_ID={{ env "NOMAD_ALLOC_ID" }}
NOMAD_ALLOC_NAME={{ env "NOMAD_ALLOC_NAME" }}
EOH
        destination = "local/app.env"
        env         = true
      }

      resources {
        cpu    = 1000  # MHz - CPU-only processing
        memory = 4096  # MB - Increased for CPU WhisperLive stability
      }

      # Startup command for CPU version
      template {
        data = <<EOH
#!/bin/sh
if [ "$DEVICE_TYPE" = "cpu" ]; then
  echo 'INFO: DEVICE_TYPE is cpu, starting WhisperLive CPU service.'
  exec python3 /app/run_server.py --port 9090 --backend faster_whisper -fw /root/.cache/huggingface/hub/models--Systran--faster-whisper-tiny/snapshots/d90ca5fe260221311c53c58e660288d3deb8d356
else
  echo "INFO: DEVICE_TYPE is not cpu (it is '$DEVICE_TYPE'), WhisperLive CPU service will not start. Sleeping indefinitely."
  sleep infinity
fi
EOH
        destination = "local/start.sh"
        perms = "755"
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