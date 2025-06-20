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
    
    # Use host networking for simplicity during development
    network {
      mode = "host"
    }

    task "vexa-bot" {
      driver = "docker"
      
      config {
        # Use the freshly built dev vexa-bot image with browser automation
        image = "services/vexa-bot:dev"
        force_pull = false
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
BOT_LANGUAGE={{ or (env "NOMAD_META_language") "en" }}
BOT_TASK={{ or (env "NOMAD_META_task") "transcribe" }}
BOT_USER_TOKEN={{ or (env "NOMAD_META_user_token") "" }}
EOH
        destination = "local/bot.env"
        env         = true
      }

      # Template for BOT_CONFIG using toJSON (KAD-13) - fixes shell parsing issue
      template {
        data = <<EOH
{{ $platform := env "NOMAD_META_platform" | regexReplaceAll "-" "_" -}}
{{ $meetingUrl := or (env "NOMAD_META_meeting_url") "" -}}
{{ $botName := or (env "NOMAD_META_bot_name") "Vexa Bot" -}}
{{ $token := or (env "NOMAD_META_user_token") "" -}}
{{ $connectionId := env "NOMAD_META_connection_id" -}}
{{ $nativeMeetingId := env "NOMAD_META_native_meeting_id" -}}
{{ $language := or (env "NOMAD_META_language") "en" -}}
{{ $task := or (env "NOMAD_META_task") "transcribe" -}}
{{ $meetingId := or (env "NOMAD_META_meeting_id") "0" -}}
{{ $redisUrl := "redis://172.17.0.1:31357" -}}
{{ $jsonString := printf `{"platform":"%s","meetingUrl":"%s","botName":"%s","token":"%s","connectionId":"%s","nativeMeetingId":"%s","language":"%s","task":"%s","redisUrl":"%s","automaticLeave":{"waitingRoomTimeout":300000,"noOneJoinedTimeout":60000,"everyoneLeftTimeout":30000},"meeting_id":%s,"reconnectionIntervalMs":5000,"botManagerCallbackUrl":"http://localhost:8080/bots/internal/callback/exited"}` $platform $meetingUrl $botName $token $connectionId $nativeMeetingId $language $task $redisUrl $meetingId -}}
BOT_CONFIG={{ $jsonString | toJSON }}
EOH
        destination = "local/bot-config.env"
        env         = true
      }

      # Increased resources for browser automation and video processing
      resources {
        cpu    = 1000 # MHz - browser automation is CPU intensive
        memory = 2048 # MB - Chrome needs significant memory
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