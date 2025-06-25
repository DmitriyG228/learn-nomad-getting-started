#!/bin/bash

# WhisperLive Autoscaling Monitor
# ==============================
# Real-time monitoring dashboard for WhisperLive autoscaling system
# Shows metrics, job status, and scaling decisions in one view

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration
REFRESH_INTERVAL="${1:-5}"  # Default 5 seconds
METRICS_URL="http://192.168.1.4:9105/"

echo_header() {
    echo -e "${BOLD}${CYAN}$1${NC}"
}

echo_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

echo_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to get current timestamp
get_timestamp() {
    date '+%H:%M:%S'
}

# Function to get WhisperLive metrics
get_whisperlive_metrics() {
    echo_header "=== WhisperLive Metrics ($(get_timestamp)) ==="
    
    local metrics_output=""
    if metrics_output=$(curl -s --max-time 3 "$METRICS_URL" 2>/dev/null); then
        echo "$metrics_output" | grep -E "whisperlive_(servers|sessions_average|sessions_all_total)" | while read -r line; do
            if [[ "$line" =~ whisperlive_servers ]]; then
                echo -e "${GREEN}📊 $line${NC}"
            elif [[ "$line" =~ whisperlive_sessions_average ]]; then
                local avg=$(echo "$line" | awk '{print $2}')
                if (( $(echo "$avg > 3" | bc -l 2>/dev/null || echo 0) )); then
                    echo -e "${RED}🔥 $line (SCALE OUT TRIGGER!)${NC}"
                elif (( $(echo "$avg < 1" | bc -l 2>/dev/null || echo 0) )); then
                    echo -e "${BLUE}❄️  $line (scale in eligible)${NC}"
                else
                    echo -e "${YELLOW}⚖️  $line${NC}"
                fi
            else
                echo -e "${CYAN}📈 $line${NC}"
            fi
        done
    else
        echo_error "Unable to fetch metrics from $METRICS_URL"
    fi
    echo
}

# Function to get job counts and status
get_job_status() {
    echo_header "=== Job Status & Scaling ==="
    
    # WhisperLive jobs
    for job in whisperlive-cpu whisperlive-gpu; do
        local status=$(nomad job status "$job" 2>/dev/null | grep "Status" | awk '{print $3}' || echo "not-found")
        local count=""
        local running=""
        
        if [ "$status" != "not-found" ]; then
            count=$(nomad job status "$job" 2>/dev/null | grep "Desired" | awk '{print $2}' || echo "?")
            running=$(nomad job status "$job" 2>/dev/null | grep -c "running" || echo "0")
            
            if [ "$status" = "running" ]; then
                echo_success "$job: $running/$count instances running"
            else
                echo_warning "$job: $status (desired: $count)"
            fi
        else
            echo_error "$job: not deployed"
        fi
    done
    
    # Infrastructure services
    echo
    echo_header "=== Infrastructure Services ==="
    for service in whisperlive-metrics-exporter prometheus nomad-autoscaler; do
        local status=$(nomad job status "$service" 2>/dev/null | grep "Status" | awk '{print $3}' || echo "not-found")
        
        if [ "$status" = "running" ]; then
            echo_success "$service: $status"
        elif [ "$status" = "pending" ]; then
            echo_warning "$service: $status"
        else
            echo_error "$service: $status"
        fi
    done
    echo
}

# Function to show recent scaling events
get_scaling_events() {
    echo_header "=== Recent Scaling Events ==="
    
    # Check autoscaler logs if available
    local autoscaler_alloc=$(nomad job allocs nomad-autoscaler 2>/dev/null | grep running | awk '{print $1}' | head -1)
    if [ -n "$autoscaler_alloc" ]; then
        echo_info "Autoscaler logs (last 5 lines):"
        nomad alloc logs --tail=5 "$autoscaler_alloc" 2>/dev/null | grep -E "(scaling|policy|threshold|recommendation)" || echo "No recent scaling activity"
    else
        echo_warning "Nomad Autoscaler not running - check deployment"
    fi
    
    # Check for recent job modifications
    echo
    echo_info "Recent job modifications:"
    nomad job history whisperlive-cpu 2>/dev/null | head -3 | tail -2 || echo "No CPU job history"
    nomad job history whisperlive-gpu 2>/dev/null | head -3 | tail -2 || echo "No GPU job history"
    echo
}

# Function to show active bots
get_active_bots() {
    echo_header "=== Active Bot Sessions ==="
    
    local bot_count=$(nomad job status -short 2>/dev/null | grep "vexa-bot/dispatch-" | grep -c "running" || echo "0")
    if [ "$bot_count" -gt 0 ]; then
        echo_success "$bot_count active bot sessions"
        nomad job status -short 2>/dev/null | grep "vexa-bot/dispatch-" | grep "running" | head -5
        if [ "$bot_count" -gt 5 ]; then
            echo "... and $((bot_count - 5)) more"
        fi
    else
        echo_info "No active bot sessions"
    fi
    echo
}

# Function to show Redis data
get_redis_data() {
    echo_header "=== Redis WhisperLive Data ==="
    
    # Try to access Redis through running container
    local redis_containers=$(docker ps --filter "name=redis" --format "{{.Names}}" 2>/dev/null || echo "")
    
    if [ -n "$redis_containers" ]; then
        local redis_container=$(echo "$redis_containers" | head -1)
        echo_info "Checking Redis rankings in container: $redis_container"
        
        local wl_data=$(docker exec "$redis_container" redis-cli ZRANGE wl:rank 0 -1 WITHSCORES 2>/dev/null || echo "")
        if [ -n "$wl_data" ]; then
            echo "$wl_data" | while read -r server && read -r sessions; do
                if [ -n "$server" ] && [ -n "$sessions" ]; then
                    echo_success "Server: $server → $sessions sessions"
                fi
            done
        else
            echo_info "No WhisperLive servers registered in Redis"
        fi
    else
        echo_warning "No Redis container found"
    fi
    echo
}

# Function to show recommendations
show_monitoring_commands() {
    echo_header "=== Manual Monitoring Commands ==="
    echo_info "Test metrics endpoint:     curl http://192.168.1.4:9105/"
    echo_info "Check job status:          nomad job status whisperlive-gpu"
    echo_info "View autoscaler logs:      nomad alloc logs \$(nomad job allocs nomad-autoscaler | grep running | awk '{print \$1}')"
    echo_info "Generate test load:        ./scripts/test-autoscaling.sh 5"
    echo_info "Monitor Redis directly:    ./vexa/monitor_redis_wl.sh"
    echo
}

# Main monitoring loop
main() {
    echo_header "🚀 WhisperLive Autoscaling Monitor"
    echo_info "Refresh interval: ${REFRESH_INTERVAL}s | Press Ctrl+C to exit"
    echo_info "Metrics endpoint: $METRICS_URL"
    echo "="
    
    while true; do
        clear
        echo_header "🚀 WhisperLive Autoscaling Monitor - $(get_timestamp)"
        echo
        
        get_whisperlive_metrics
        get_job_status
        get_active_bots
        get_scaling_events
        get_redis_data
        show_monitoring_commands
        
        echo_info "Refreshing in ${REFRESH_INTERVAL}s... (Press Ctrl+C to exit)"
        sleep "$REFRESH_INTERVAL"
    done
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n${GREEN}Monitoring stopped${NC}"; exit 0' INT

# Check dependencies
if ! command -v bc &> /dev/null; then
    echo_warning "Installing 'bc' for calculations..."
    # Note: User may need to install bc manually
fi

# Run the monitor
main 