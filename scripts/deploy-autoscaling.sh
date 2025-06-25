#!/bin/bash

# Deploy WhisperLive Autoscaling Infrastructure
# ============================================
# This script deploys the autoscaling infrastructure in the correct order:
# 1. Metrics exporter (collects WhisperLive stats from Redis)  
# 2. Prometheus (scrapes metrics)
# 3. Nomad Autoscaler (makes scaling decisions)
# 4. Update WhisperLive jobs with scaling policies

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

# Function to wait for job to be running
wait_for_job() {
    local job_name="$1"
    local max_wait="${2:-120}"  # Default 2 minutes
    
    echo_info "Waiting for job '$job_name' to be running..."
    
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        local status=$(nomad job status "$job_name" 2>/dev/null | grep "Status" | awk '{print $3}' || echo "not-found")
        
        if [ "$status" = "running" ]; then
            # Check if allocations are actually running
            local running_allocs=$(nomad job status "$job_name" | grep -c "running" || echo "0")
            if [ "$running_allocs" -gt 0 ]; then
                echo_success "Job '$job_name' is running with $running_allocs allocation(s)"
                return 0
            fi
        fi
        
        echo -n "."
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    echo_error "Job '$job_name' failed to start within ${max_wait}s"
    nomad job status "$job_name" || true
    return 1
}

# Function to check if service is healthy
check_service_health() {
    local service_name="$1"
    local max_wait="${2:-60}"
    
    echo_info "Checking health of service '$service_name'..."
    
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        # Try to get service health from Nomad
        local healthy=$(nomad service list | grep "$service_name" | grep -c "passing" || echo "0")
        
        if [ "$healthy" -gt 0 ]; then
            echo_success "Service '$service_name' is healthy"
            return 0
        fi
        
        echo -n "."
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    echo_warning "Service '$service_name' health check timed out (may still be starting)"
    return 0  # Don't fail deployment for health check timeouts
}

echo_info "Starting WhisperLive Autoscaling Infrastructure Deployment"
echo_info "========================================================="

# Step 1: Deploy WhisperLive Metrics Exporter
echo_info "Step 1: Deploying WhisperLive Metrics Exporter..."
nomad job run jobs/whisperlive-metrics-exporter.nomad.hcl
wait_for_job "whisperlive-metrics-exporter"
check_service_health "whisperlive-metrics"

# Step 2: Deploy Prometheus
echo_info "Step 2: Deploying Prometheus..."
nomad job run jobs/prometheus.nomad.hcl
wait_for_job "prometheus"
check_service_health "prometheus"

# Step 3: Deploy Nomad Autoscaler
echo_info "Step 3: Deploying Nomad Autoscaler..."
nomad job run jobs/nomad-autoscaler.nomad.hcl
wait_for_job "nomad-autoscaler"
check_service_health "nomad-autoscaler"

# Step 4: Update WhisperLive jobs with scaling policies
echo_info "Step 4: Updating WhisperLive jobs with autoscaling policies..."

# Check if WhisperLive jobs are already running
cpu_running=$(nomad job status whisperlive-cpu 2>/dev/null | grep -c "running" || echo "0")
gpu_running=$(nomad job status whisperlive-gpu 2>/dev/null | grep -c "running" || echo "0")

if [ "$cpu_running" -gt 0 ]; then
    echo_info "Updating running WhisperLive CPU job with scaling policy..."
    nomad job run jobs/whisperlive-cpu.nomad.hcl
    wait_for_job "whisperlive-cpu"
else
    echo_warning "WhisperLive CPU job not running. Start it manually with: nomad job run jobs/whisperlive-cpu.nomad.hcl"
fi

if [ "$gpu_running" -gt 0 ]; then
    echo_info "Updating running WhisperLive GPU job with scaling policy..."
    nomad job run jobs/whisperlive-gpu.nomad.hcl
    wait_for_job "whisperlive-gpu"
else
    echo_warning "WhisperLive GPU job not running. Start it manually with: nomad job run jobs/whisperlive-gpu.nomad.hcl"
fi

echo_success "Autoscaling infrastructure deployment completed!"
echo_info ""
echo_info "Services deployed:"
echo_info "- WhisperLive Metrics Exporter: http://localhost:9105/metrics"
echo_info "- Prometheus: http://localhost:9090"
echo_info "- Nomad Autoscaler: http://localhost:8080"
echo_info ""
echo_info "Test the metrics exporter:"
echo_info "  curl http://localhost:9105/metrics"
echo_info ""
echo_info "View WhisperLive metrics in Prometheus:"
echo_info "  http://localhost:9090/graph?g0.expr=whisperlive_sessions_average"
echo_info ""
echo_info "Monitor autoscaler logs:"
echo_info "  nomad alloc logs -f \$(nomad job allocs nomad-autoscaler | grep running | awk '{print \$1}')" 