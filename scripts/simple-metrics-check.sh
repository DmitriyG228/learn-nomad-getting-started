#!/bin/bash

# Simple WhisperLive Metrics Check
# ================================
# One-shot status check for autoscaling system

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔍 WhisperLive Autoscaling Status Check${NC}"
echo "======================================"

# 1. Check metrics endpoint
echo
echo -e "${YELLOW}📊 Current Metrics:${NC}"
if curl -s --max-time 5 http://192.168.1.4:9105/ 2>/dev/null; then
    echo -e "${GREEN}✅ Metrics exporter responding${NC}"
else
    echo -e "${RED}❌ Metrics exporter not responding${NC}"
fi

# 2. Check job counts
echo
echo -e "${YELLOW}🏗️  Job Counts:${NC}"
for job in whisperlive-cpu whisperlive-gpu; do
    if count=$(nomad job status "$job" 2>/dev/null | grep -E "Desired|Running" | awk 'NR==1{print $2}'); then
        running=$(nomad job status "$job" 2>/dev/null | grep -c "running" || echo "0")
        echo -e "${GREEN}$job: $running/$count instances${NC}"
    else
        echo -e "${RED}$job: not found${NC}"
    fi
done

# 3. Check active bots
echo
echo -e "${YELLOW}🤖 Active Bots:${NC}"
bot_count=$(nomad job status -short 2>/dev/null | grep "vexa-bot/dispatch-" | grep -c "running" || echo "0")
echo -e "${GREEN}Active bot sessions: $bot_count${NC}"

# 4. Check scaling thresholds
echo
echo -e "${YELLOW}⚖️  Scaling Triggers:${NC}"
echo "Scale OUT when: whisperlive_sessions_average > 3"
echo "Scale IN when:  whisperlive_sessions_average < 1"
echo "Cooldown:       2 minutes between actions"

echo
echo -e "${BLUE}💡 Quick Commands:${NC}"
echo "Monitor live:     ./scripts/monitor-autoscaling.sh"
echo "Test load:        ./scripts/test-autoscaling.sh 5"
echo "Check Redis:      ./vexa/monitor_redis_wl.sh" 