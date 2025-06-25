#!/usr/bin/env bash

# WhisperLive Metrics Exporter Script
# ----------------------------------
# This script retrieves WhisperLive server statistics stored in Redis (wl:rank
# sorted-set) and outputs them in Prometheus-compatible text format **to STDOUT**.
#
# Typical usage:
#   ./whisperlive_metrics.sh            # Uses defaults, prints metrics
#   REDIS_HOST=redis REDIS_PORT=6379 ./whisperlive_metrics.sh
#
# The generated metrics can be scraped directly by Prometheus when this script
# is executed under a lightweight web-server (e.g. via `socat` or `docker exec
# /metrics`).  Alternatively, it can be scheduled via cron and its output
# redirected into a Node-Exporter textfile collector directory.
#
# ----------------------------------

set -euo pipefail

# Redis connection (override via env vars)
REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"  # optional
REDIS_CLI="redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT}"
if [[ -n "$REDIS_PASSWORD" ]]; then
  REDIS_CLI+=" -a ${REDIS_PASSWORD}"
fi

# Query wl:rank and return a newline-separated list "url sessions"
readarray -t RANKINGS < <($REDIS_CLI ZRANGE wl:rank 0 -1 WITHSCORES 2>/dev/null)

# Guard: No servers
if [[ ${#RANKINGS[@]} -eq 0 ]]; then
  echo "# whisperlive metrics (no servers registered)"
  echo "whisperlive_servers 0"
  exit 0
fi

# Build metrics
TOTAL_SERVERS=0
TOTAL_SESSIONS=0

printf "# HELP whisperlive_sessions_total Number of active sessions per WhisperLive instance.\n"
printf "# TYPE whisperlive_sessions_total gauge\n"

for (( i=0; i<${#RANKINGS[@]}; i+=2 )); do
  SERVER_URL="${RANKINGS[$i]}"
  SESSIONS="${RANKINGS[$i+1]}"
  ((TOTAL_SERVERS++))
  ((TOTAL_SESSIONS+=SESSIONS))
  # Escape label value per Prometheus guidelines (replace "\" and "\n")
  SAFE_URL=$(echo "$SERVER_URL" | sed 's/\\/\\\\/g; s/\"/\\"/g')
  printf 'whisperlive_sessions_total{server="%s"} %s\n' "$SAFE_URL" "$SESSIONS"
  # Track min usage (for down-scaling decisions)
  if [[ $i -eq 0 ]] || [[ $SESSIONS -lt $MIN_SESSIONS ]]; then
    MIN_SESSIONS=$SESSIONS
    MIN_SERVER=$SERVER_URL
  fi
done

# Aggregate metrics
printf "# HELP whisperlive_servers Total number of registered WhisperLive servers.\n"
printf "# TYPE whisperlive_servers gauge\n"
printf "whisperlive_servers %s\n" "$TOTAL_SERVERS"

printf "# HELP whisperlive_sessions_all_total Total number of active sessions across all WhisperLive servers.\n"
printf "# TYPE whisperlive_sessions_all_total gauge\n"
printf "whisperlive_sessions_all_total %s\n" "$TOTAL_SESSIONS"

AVG=$(awk -v total="${TOTAL_SESSIONS}" -v servers="${TOTAL_SERVERS}" 'BEGIN{ if(servers==0) print 0; else printf "%.2f", total/servers }')
printf "# HELP whisperlive_sessions_average Average number of sessions per WhisperLive server.\n"
printf "# TYPE whisperlive_sessions_average gauge\n"
printf "whisperlive_sessions_average %s\n" "$AVG"

# Provide labels for the least-loaded server (useful for scale-in targeting)
printf "# HELP whisperlive_least_loaded_sessions Current session count on the least loaded server.\n"
printf "# TYPE whisperlive_least_loaded_sessions gauge\n"
printf 'whisperlive_least_loaded_sessions{server="%s"} %s\n' "$MIN_SERVER" "$MIN_SESSIONS" 