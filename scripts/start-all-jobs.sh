#!/bin/bash
# Start all Vexa jobs in dependency order with TARGET support
set -e

TARGET=${TARGET:-cpu}

echo "🚀 Starting all Vexa jobs in dependency order..."
echo "🎯 TARGET=$TARGET (WhisperLive deployment mode)"

# 1. Infrastructure first (database, cache)
echo "📦 Starting infrastructure services..."
nomad job run jobs/redis.nomad.hcl

# 2. Core services that depend on infrastructure
echo "📦 Starting core services..."
nomad job run jobs/admin-api.nomad.hcl
nomad job run jobs/bot-manager.nomad.hcl
nomad job run jobs/transcription-collector.nomad.hcl

# 3. Processing services - TARGET dependent
echo "📦 Starting processing services..."
if [ "$TARGET" = "gpu" ]; then
    echo "🎮 Deploying GPU WhisperLive services..."
    nomad job run jobs/whisperlive-gpu.nomad.hcl
    echo "💻 Also starting CPU WhisperLive as fallback..."
    nomad job run jobs/whisperlive-cpu.nomad.hcl
else
    echo "💻 Deploying CPU WhisperLive services..."
nomad job run jobs/whisperlive-cpu.nomad.hcl
fi

# 4. Frontend/gateway last
echo "📦 Starting frontend services..."
nomad job run jobs/api-gateway.nomad.hcl

# 5. Register parameterized jobs (don't auto-start)
echo "📦 Registering parameterized jobs..."
nomad job run jobs/vexa-bot.nomad.hcl

echo "✅ All jobs started successfully with TARGET=$TARGET!"
echo ""
echo "🔍 Check status: nomad job status"
echo "🌐 Access API Gateway at: $(nomad service info api-gateway 2>/dev/null | grep Address | awk '{print "http://"$2}' | head -1 || echo 'API Gateway starting...')"
echo ""
if [ "$TARGET" = "gpu" ]; then
    echo "🎮 GPU WhisperLive: Deployed (requires NVIDIA drivers)"
    echo "💻 CPU WhisperLive: Deployed as fallback"
else
    echo "💻 CPU WhisperLive: Deployed"
    echo "ℹ️  Use TARGET=gpu for GPU deployment"
fi
