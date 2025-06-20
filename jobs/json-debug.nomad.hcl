job "json-debug" {
  datacenters = ["dc1"]
  type        = "batch"
  
  # Make this parameterized so we can dispatch it with metadata
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

  group "g" {
    task "check" {
      driver = "docker"
      config {
        image = "services/json-debug:dev"
        force_pull = false
      }

      # Test the exact same template pattern as the bot job
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
{{ $jsonString := printf `{"platform":"%s","meetingUrl":"%s","botName":"%s","token":"%s","connectionId":"%s","nativeMeetingId":"%s","language":"%s","task":"%s","redisUrl":"redis://172.17.0.1:31008","automaticLeave":{"waitingRoomTimeout":300000,"noOneJoinedTimeout":60000,"everyoneLeftTimeout":30000},"meeting_id":%s,"reconnectionIntervalMs":5000,"botManagerCallbackUrl":"http://localhost:8080/bots/internal/callback/exited"}` $platform $meetingUrl $botName $token $connectionId $nativeMeetingId $language $task $meetingId -}}
BOT_CONFIG={{ $jsonString | toJSON }}
EOH
        destination = "local/env"
        env         = true
      }

      resources { 
        cpu = 100 
        memory = 64 
      }
    }
  }
} 