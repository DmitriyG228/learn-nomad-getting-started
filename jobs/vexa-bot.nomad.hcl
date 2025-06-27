job "vexa-bot" {
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

  group "bot" {
    count = 1
    
    network {
      mode = "bridge"
    }

    task "vexa-bot" {
      driver = "docker"
      
      config {
        # Use the freshly built dev vexa-bot image with browser automation
        image = "vexaai/vexa-bot:dev"
        force_pull = false
      }

      # This template ensures that the dependent services are available before
      # the other templates are rendered. It does not create environment variables.
      template {
        data = <<EOH
{{ range nomadService "redis" }}{{ end }}
{{ range nomadService "bot-manager" }}{{ end }}
EOH
        destination = "local/dependencies"
        change_mode = "noop"
      }

      # Template block converts dispatch metadata into environment variables
      template {
        data = <<EOH
BOT_CONNECTION_ID={{ env "NOMAD_META_connection_id" }}
BOT_USER_ID={{ env "NOMAD_META_user_id" }}
BOT_MEETING_ID={{ env "NOMAD_META_meeting_id" }}
BOT_PLATFORM={{ env "NOMAD_META_platform" }}
BOT_NATIVE_MEETING_ID={{ env "NOMAD_META_native_meeting_id" }}
BOT_MEETING_URL={{ or (env "NOMAD_META_meeting_url") "" }}
BOT_NAME={{ or (env "NOMAD_META_bot_name") "Vexa Bot" }}
BOT_LANGUAGE={{ env "NOMAD_META_language" }}
BOT_TASK={{ or (env "NOMAD_META_task") "transcribe" }}
BOT_USER_TOKEN={{ or (env "NOMAD_META_user_token") "" }}
{{ range nomadService "redis" -}}
REDIS_URL=redis://{{ .Address }}:{{ .Port }}/0
{{ end }}
EOH
        destination = "local/bot.env"
        env         = true
      }

      # Template for BOT_CONFIG using toJSON (KAD-13) - PROPER NOMAD SERVICE DISCOVERY PATTERN
      template {
        data = <<EOH
{{ $platform := env "NOMAD_META_platform" -}}
{{ $meetingUrl := or (env "NOMAD_META_meeting_url") "" -}}
{{ $botName := or (env "NOMAD_META_bot_name") "Vexa Bot" -}}
{{ $token := env "NOMAD_META_user_token" -}}
{{ $connectionId := env "NOMAD_META_connection_id" -}}
{{ $nativeMeetingId := env "NOMAD_META_native_meeting_id" -}}
{{ $language := env "NOMAD_META_language" -}}
{{ $task := or (env "NOMAD_META_task") "transcribe" -}}
{{ $meetingId := or (env "NOMAD_META_meeting_id") "0" -}}
{{ $redisUrl := "redis://127.0.0.1:6379/0" -}}
{{ $botManagerUrl := "http://127.0.0.1:8080" -}}
{{ range nomadService "redis" -}}
{{ $redisUrl = printf "redis://%s:%v/0" .Address .Port -}}
{{ end -}}
{{ range nomadService "bot-manager" -}}
{{ $botManagerUrl = printf "http://%s:%v" .Address .Port -}}
{{ end -}}
{{ $langValue := "null" -}}
{{ if $language }}{{ $langValue = printf `"%s"` $language }}{{ end -}}
{{ $tokenValue := "null" -}}
{{ if $token }}{{ $tokenValue = printf `"%s"` $token }}{{ end -}}
{{ $jsonString := printf `{"platform":"%s","meetingUrl":"%s","botName":"%s","token":%s,"connectionId":"%s","nativeMeetingId":"%s","language":%s,"task":"%s","redisUrl":"%s","automaticLeave":{"waitingRoomTimeout":300000,"noOneJoinedTimeout":60000,"everyoneLeftTimeout":30000},"meeting_id":%s,"reconnectionIntervalMs":5000,"botManagerCallbackUrl":"%s/bots/internal/callback/exited"}` $platform $meetingUrl $botName $tokenValue $connectionId $nativeMeetingId $langValue $task $redisUrl $meetingId $botManagerUrl -}}
BOT_CONFIG={{ $jsonString | toJSON }}
EOH
        destination = "local/bot-config.env"
        env         = true
      }

      # Increased resources for browser automation and video processing (2x boost)
      resources {
        cpu    = 500 # MHz - browser automation is CPU intensive (2x: 250->500)
        memory = 1024 # MB - Chrome needs significant memory (2x: 512->1024)
      }
      
      # Restart policy for batch jobs
      restart {
        attempts = 2
        interval = "30m"
        delay    = "15s"
        mode     = "fail"
      }
    }
  }
} 