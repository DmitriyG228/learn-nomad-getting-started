job "whisperlive-metrics-exporter" {
  datacenters = ["dc1"]
  type        = "service"

  group "exporter" {
    count = 1

    network {
      port "metrics" {
        static = 9105
      }
    }

    service {
      name = "whisperlive-metrics"
      port = "metrics"
      provider = "nomad"
      
      check {
        type     = "http"
        path     = "/metrics"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "metrics-exporter" {
      driver = "docker"

      config {
        image = "alpine:latest"
        ports = ["metrics"]
        
        entrypoint = ["/bin/sh"]
        command = "/local/start.sh"
      }

      # Simple startup script without Consul dependency
      template {
        destination = "local/start.sh"
        perms = "755"
        data = <<EOH
#!/bin/sh
set -e

# Install dependencies
apk add --no-cache socat redis

# Create HTTP response wrapper script
cat > /tmp/http_metrics.sh << 'HTTP_SCRIPT'
#!/bin/sh

# Create proper HTTP response
echo "HTTP/1.1 200 OK"
echo "Content-Type: text/plain; version=0.0.4"
echo "Connection: close"
echo ""

# Run the actual metrics script
/tmp/metrics.sh
HTTP_SCRIPT

# Create metrics script
cat > /tmp/metrics.sh << 'SCRIPT'
#!/bin/sh

# Try to connect to Redis via Nomad service discovery first
{{ with nomadService "redis" }}{{ with index . 0 }}redis_host="{{ .Address }}"
redis_port="{{ .Port }}"{{ end }}{{ else }}# No Redis service found
echo "# ERROR: Redis service not available via Nomad service discovery"
echo "whisperlive_servers 0"
echo "whisperlive_sessions_all_total 0"
echo "whisperlive_sessions_average 0"
exit 1{{ end }}

# Query Redis for WhisperLive rankings
result=$(redis-cli -h "$redis_host" -p "$redis_port" ZRANGE wl:rank 0 -1 WITHSCORES 2>/dev/null || echo "")

if [ -z "$result" ]; then
  echo "# whisperlive metrics (no servers registered or Redis unavailable)"
  echo "whisperlive_servers 0"
  echo "whisperlive_sessions_all_total 0"
  echo "whisperlive_sessions_average 0"
  exit 0
fi

# Process results
total_servers=0
total_sessions=0

echo "# HELP whisperlive_sessions_total Number of active sessions per WhisperLive instance."
echo "# TYPE whisperlive_sessions_total gauge"

echo "$result" | {
  while read -r server && read -r sessions; do
    if [ -n "$server" ] && [ -n "$sessions" ]; then
      total_servers=$((total_servers + 1))
      total_sessions=$((total_sessions + sessions))
      echo "whisperlive_sessions_total{server=\"$server\"} $sessions"
    fi
  done
  
  echo "# HELP whisperlive_servers Total number of registered WhisperLive servers."
  echo "# TYPE whisperlive_servers gauge"
  echo "whisperlive_servers $total_servers"
  
  echo "# HELP whisperlive_sessions_all_total Total number of active sessions across all servers."
  echo "# TYPE whisperlive_sessions_all_total gauge"
  echo "whisperlive_sessions_all_total $total_sessions"
  
  echo "# HELP whisperlive_sessions_average Average number of sessions per server."
  echo "# TYPE whisperlive_sessions_average gauge"
  if [ $total_servers -gt 0 ]; then
    avg=$(awk "BEGIN {printf \"%.2f\", $total_sessions/$total_servers}")
    echo "whisperlive_sessions_average $avg"
  else
    echo "whisperlive_sessions_average 0"
  fi
}
SCRIPT

chmod +x /tmp/metrics.sh
chmod +x /tmp/http_metrics.sh

# Start HTTP server with proper HTTP/1.1 responses
exec socat TCP-LISTEN:9105,fork,reuseaddr EXEC:/tmp/http_metrics.sh
EOH
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
} 