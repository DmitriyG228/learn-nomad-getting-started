job "whisperlive-gpu" {
  datacenters = ["dc1"]
  type        = "service"

  # Enable GPU constraint
  constraint {
    attribute = "${attr.driver.docker.nvidia_driver_version}"
    operator  = "is_set"
  }

  group "whisperlive" {
    count = 3  # Match docker-compose replicas

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
      name = "whisperlive"
      port = "ws"
      provider = "nomad"

      check {
        type     = "http"
        port     = "health"
        path     = "/health"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "whisperlive-server" {
      driver = "docker"

      config {
        image = "vexaai/whisperlive:gpu-dev"
        ports = ["ws", "health"]
        force_pull = false

        # GPU configuration
        devices = [
          {
            host_path      = "/dev/nvidia3"
            container_path = "/dev/nvidia3"
          }
        ]

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
# Use Redis Stream URL instead of WebSocket URL
{{ with nomadService "redis" }}{{ with index . 0 }}REDIS_STREAM_URL=redis://{{ .Address }}:{{ .Port }}/0/transcription_segments
TRANSCRIPTION_COLLECTOR_URL=redis://{{ .Address }}:{{ .Port }}/0/transcription_segments
REDIS_URL=redis://{{ .Address }}:{{ .Port }}/0
REDIS_HOST={{ .Address }}
REDIS_PORT={{ .Port }}{{ end }}{{ end }}
REDIS_DB=0
REDIS_STREAM_NAME=transcription_segments
LANGUAGE_DETECTION_SEGMENTS=${LANGUAGE_DETECTION_SEGMENTS}
VAD_FILTER_THRESHOLD=${VAD_FILTER_THRESHOLD}
DEVICE_TYPE=cuda
# Nomad-specific environment for URL registration
NOMAD_ALLOC_ID={{ env "NOMAD_ALLOC_ID" }}
NOMAD_ALLOC_NAME={{ env "NOMAD_ALLOC_NAME" }}
EOH
        destination = "local/app.env"
        env         = true
      }

      # GPU device requirement
      resources {
        cpu    = 2000  # MHz - GPU processing needs CPU support
        memory = 4096  # MB - Model loading requires significant memory
        
        device "nvidia/gpu" {
          count = 1
          
          constraint {
            attribute = "${device.attr.compute_capability}"
            operator  = ">="
            value     = "6.0"
          }
        }
      }

      # Startup command that checks device type and starts appropriate service
      template {
        data = <<EOH
#!/bin/sh
if [ "$DEVICE_TYPE" = "cuda" ]; then
  echo 'INFO: DEVICE_TYPE is cuda, starting WhisperLive GPU service.'
  exec python3 /app/run_server.py --port 9090 --backend faster_whisper -fw /root/.cache/huggingface/hub/models--Systran--faster-whisper-medium/snapshots/08e178d48790749d25932bbc082711ddcfdfbc4f
else
  echo "INFO: DEVICE_TYPE is not cuda (it is '$DEVICE_TYPE'), WhisperLive GPU service will not start. Sleeping indefinitely."
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