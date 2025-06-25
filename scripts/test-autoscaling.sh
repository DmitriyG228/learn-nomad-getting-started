#!/bin/bash

# Test WhisperLive Autoscaling
# ============================
# This script tests the autoscaling by:
# 1. Creating load (dispatching multiple bots)
# 2. Monitoring metrics and scaling decisions
# 3. Reducing load and verifying scale-in

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

echo_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
BOT_COUNT="${1:-5}"  # Number of bots to create
TEST_DURATION="${2:-300}"  # Test duration in seconds (5 minutes default)

echo_info "WhisperLive Autoscaling Test"
echo_info "============================"
echo_info "Bot count: $BOT_COUNT"
echo_info "Test duration: ${TEST_DURATION}s"
echo_info ""

# Function to get current metrics
get_metrics() {
    echo_info "Current WhisperLive metrics:"
    curl -s http://localhost:9105/metrics | grep -E "whisperlive_(servers|sessions_average|sessions_all_total)" || echo "Metrics not available"
    echo ""
}

# Function to get current job counts
get_job_counts() {
    echo_info "Current WhisperLive job counts:"
    echo -n "CPU instances: "
    nomad job status whisperlive-cpu 2>/dev/null | grep "Desired" | awk '{print $2}' || echo "Job not found"
    echo -n "GPU instances: "
    nomad job status whisperlive-gpu 2>/dev/null | grep "Desired" | awk '{print $2}' || echo "Job not found"
    echo ""
}

# Function to dispatch bots
dispatch_bots() {
    local count=$1
    echo_info "Dispatching $count bots to create load..."
    
    local dispatched=0
    for i in $(seq 1 $count); do
        # Create bot dispatch payload
        local payload=$(cat <<EOF
{
  "bot_config": {
    "platform": "google_meet",
    "meeting_url": "https://meet.google.com/test-$i",
    "transcription_config": {
      "language": null,
      "user_token": null
    }
  }
}
EOF
        )
        
        # Dispatch bot (assuming bot-manager API is available)
        if nomad job dispatch -meta="bot_config=$(echo "$payload" | jq -c .bot_config)" vexa-bot >/dev/null 2>&1; then
            dispatched=$((dispatched + 1))
            echo -n "."
        else
            echo_warning "Failed to dispatch bot $i"
        fi
    done
    
    echo ""
    echo_success "Successfully dispatched $dispatched/$count bots"
}

# Function to monitor for a specified duration
monitor_scaling() {
    local duration=$1
    local start_time=$(date +%s)
    local end_time=$((start_time + duration))
    
    echo_info "Monitoring scaling for ${duration}s..."
    
    while [ $(date +%s) -lt $end_time ]; do
        local elapsed=$(($(date +%s) - start_time))
        echo_info "=== Elapsed: ${elapsed}s / ${duration}s ==="
        
        get_metrics
        get_job_counts
        
        # Check autoscaler logs for scaling events
        local autoscaler_alloc=$(nomad job allocs nomad-autoscaler 2>/dev/null | grep running | awk '{print $1}' | head -1)
        if [ -n "$autoscaler_alloc" ]; then
            echo_info "Recent autoscaler activity:"
            nomad alloc logs "$autoscaler_alloc" 2>/dev/null | tail -5 | grep -E "(scaling|policy|threshold)" || echo "No recent scaling activity"
            echo ""
        fi
        
        sleep 30
    done
}

# Function to stop all bots
stop_all_bots() {
    echo_info "Stopping all bot jobs..."
    local stopped=0
    
    # Get all vexa-bot dispatch jobs
    for job in $(nomad job status -short | grep "vexa-bot/dispatch-" | awk '{print $1}'); do
        if nomad job stop "$job" >/dev/null 2>&1; then
            stopped=$((stopped + 1))
            echo -n "."
        fi
    done
    
    echo ""
    echo_success "Stopped $stopped bot jobs"
}

# Main test flow
echo_info "Phase 1: Baseline measurement"
get_metrics
get_job_counts

echo_info "Phase 2: Creating load to trigger scale-out"
dispatch_bots $BOT_COUNT

echo_info "Waiting 60s for bots to connect and register sessions..."
sleep 60

echo_info "Phase 3: Monitoring scale-out behavior"
monitor_scaling 120  # Monitor for 2 minutes

echo_info "Phase 4: Reducing load to trigger scale-in"
stop_all_bots

echo_info "Waiting 30s for sessions to drain..."
sleep 30

echo_info "Phase 5: Monitoring scale-in behavior"
monitor_scaling 120  # Monitor for 2 minutes

echo_info "Phase 6: Final state"
get_metrics
get_job_counts

echo_success "Autoscaling test completed!"
echo_info ""
echo_info "Expected behavior:"
echo_info "- Scale-out: When average sessions > 3, WhisperLive instances should increase"
echo_info "- Scale-in: When average sessions < 1, WhisperLive instances should decrease"
echo_info "- Cooldown: Changes should respect 2-minute cooldown period"
echo_info ""
echo_info "Check Prometheus graphs:"
echo_info "  http://localhost:9090/graph?g0.expr=whisperlive_sessions_average&g0.tab=0" 