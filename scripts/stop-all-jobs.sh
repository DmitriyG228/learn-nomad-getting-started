#!/bin/bash
# Stop all Vexa jobs with one command
set -e

echo "🛑 Stopping all Vexa jobs..."

# Stop all jobs - using nomad stop instead of nomad job stop to be explicit
nomad stop -yes \
  admin-api \
  api-gateway \
  bot-manager \
  redis \
  transcription-collector \
  whisperlive-cpu 2>/dev/null || true

# Stop whisperlive-gpu if it exists
nomad stop -yes whisperlive-gpu 2>/dev/null || true

echo "✅ All jobs stopped"
