job "debug-bot" {
  datacenters = ["dc1"]
  type        = "batch"
  
  # This job is parameterised - it gets dispatched by bot-manager
  parameterized {
    meta_required = [
      "connection_id",
      "user_id", 
      "meeting_id",
      "platform",
      "native_meeting_id"
    ]
    meta_optional = [
      "meeting_url",
      "bot_name",
      "language",
      "task",
      "user_token"
    ]
  }

  group "debug" {
    count = 1
    
    network {
      mode = "host"
    }

    task "debug-bot" {
      driver = "docker"
      
      config {
        image = "alpine:latest"
        command = "/bin/sh"
        args = ["-c", "echo 'Generated BOT_CONFIG:'; echo \"$BOT_CONFIG\"; echo '--- END CONFIG ---'; echo 'Testing JSON parse:'; echo \"$BOT_CONFIG\" | head -c 100; sleep 30"]
      }

      # Template for BOT_CONFIG as environment variable with proper JSON
      template {
        data = <<EOH
BOT_CONFIG={"platform":"{{ env "NOMAD_META_platform" | regexReplaceAll "-" "_" }}","meetingUrl":{{ if env "NOMAD_META_meeting_url" }}"{{ env "NOMAD_META_meeting_url" }}"{{ else }}null{{ end }},"botName":"{{ or (env "NOMAD_META_bot_name") "Vexa Bot" }}","token":"{{ or (env "NOMAD_META_user_token") "" }}","connectionId":"{{ env "NOMAD_META_connection_id" }}","nativeMeetingId":"{{ env "NOMAD_META_native_meeting_id" }}","language":"{{ or (env "NOMAD_META_language") "en" }}","task":"{{ or (env "NOMAD_META_task") "transcribe" }}","redisUrl":"redis://{{ with service "redis" }}{{ with index . 0 }}{{ .Address }}:{{ .Port }}{{ end }}{{ else }}localhost:6379{{ end }}","automaticLeave":{"waitingRoomTimeout":300000,"noOneJoinedTimeout":60000,"everyoneLeftTimeout":30000},"meeting_id":{{ env "NOMAD_META_meeting_id" }},"reconnectionIntervalMs":5000,"botManagerCallbackUrl":"http://{{ with service "bot-manager" }}{{ with index . 0 }}{{ .Address }}:{{ .Port }}{{ end }}{{ else }}localhost:8080{{ end }}/bots/internal/callback/exited"}
EOH
        destination = "local/bot-config.env"
        env         = true
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
} 