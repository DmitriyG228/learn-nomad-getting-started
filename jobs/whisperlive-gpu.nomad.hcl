job "whisperlive-gpu" {
  datacenters = ["dc1"]
  type        = "service"

  # Target GPU-enabled nodes
  constraint {
    attribute = "${meta.gpu_enabled}"
    value     = "true"
  }

  group "whisperlive" {
    count = 2  # Reduced count for testing

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
      name = "whisperlive-gpu"
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

    task "whisperlive-server" {
      driver = "docker"

      config {
        image = "vexaai/whisperlive:gpu-dev"
        ports = ["ws", "health"]
        force_pull = true

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
LANGUAGE_DETECTION_SEGMENTS=10
VAD_FILTER_THRESHOLD=0.5
DEVICE_TYPE=cuda
# Nomad-specific environment for URL registration
NOMAD_ALLOC_ID={{ env "NOMAD_ALLOC_ID" }}
NOMAD_ALLOC_NAME={{ env "NOMAD_ALLOC_NAME" }}
EOH
        destination = "local/app.env"
        env         = true
      }

      # GPU device requirement using proper Nomad device syntax
      resources {
        cpu    = 2000  # MHz - GPU processing needs CPU support
        memory = 4096  # MB - Model loading requires significant memory
        
        # Request NVIDIA GPU using device stanza
        device "nvidia/gpu" {
          count = 1
          
          # Constraint for GPU memory (optional)
          constraint {
            attribute = "${device.attr.memory}"
            operator  = ">="
            value     = "4000 MiB"
          }
        }
      }

      # Startup command that checks device type and starts appropriate service
      template {
        data = <<EOH
#!/bin/sh
echo "INFO: Starting WhisperLive GPU service"
echo "INFO: NVIDIA_VISIBLE_DEVICES=${NVIDIA_VISIBLE_DEVICES}"
echo "INFO: DEVICE_TYPE=${DEVICE_TYPE}"

# Check if GPU is available
if command -v nvidia-smi >/dev/null 2>&1; then
  echo "INFO: NVIDIA GPU detected:"
  nvidia-smi -L
else
  echo "WARNING: nvidia-smi not found in container"
fi

# Start the service
exec python3 /app/run_server.py --port 9090 --backend faster_whisper
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