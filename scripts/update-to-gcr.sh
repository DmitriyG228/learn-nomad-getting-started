#!/bin/bash

# Script to update all Nomad job files from local images to GCR images
# Usage: ./scripts/update-to-gcr.sh

set -e

# Configuration
GCP_PROJECT=${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}
GCP_REGISTRY="gcr.io/${GCP_PROJECT}"
TAG=${TAG:-dev}

echo "🔄 Updating Nomad jobs to use GCR images..."
echo "📍 GCP Project: ${GCP_PROJECT}"
echo "📍 Registry: ${GCP_REGISTRY}"
echo "📍 Tag: ${TAG}"
echo ""

if [ -z "$GCP_PROJECT" ]; then
    echo "❌ ERROR: GCP project not configured. Run: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

# Create backup directory
BACKUP_DIR="jobs/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
echo "📁 Creating backup in: $BACKUP_DIR"

# List of job files and their image mappings
declare -A JOB_MAPPINGS=(
    ["jobs/admin-api.nomad.hcl"]="services/admin-api:dev|${GCP_REGISTRY}/services/admin-api:${TAG}"
    ["jobs/api-gateway.nomad.hcl"]="services/api-gateway:dev|${GCP_REGISTRY}/services/api-gateway:${TAG}"
    ["jobs/bot-manager.nomad.hcl"]="services/bot-manager:dev|${GCP_REGISTRY}/services/bot-manager:${TAG}"
    ["jobs/transcription-collector.nomad.hcl"]="services/transcription-collector:dev|${GCP_REGISTRY}/services/transcription-collector:${TAG}"
    ["jobs/vexa-bot.nomad.hcl"]="services/vexa-bot:dev|${GCP_REGISTRY}/services/vexa-bot:${TAG}"
    ["jobs/whisperlive-cpu.nomad.hcl"]="services/whisperlive:cpu-dev|${GCP_REGISTRY}/services/whisperlive:cpu-${TAG}"
    ["jobs/whisperlive-gpu.nomad.hcl"]="services/whisperlive:gpu-dev|${GCP_REGISTRY}/services/whisperlive:gpu-${TAG}"
)

# Function to update a job file
update_job_file() {
    local job_file="$1"
    local mapping="$2"
    local old_image=$(echo "$mapping" | cut -d'|' -f1)
    local new_image=$(echo "$mapping" | cut -d'|' -f2)
    
    if [ ! -f "$job_file" ]; then
        echo "⚠️  Warning: $job_file not found, skipping..."
        return
    fi
    
    # Create backup
    cp "$job_file" "$BACKUP_DIR/"
    
    # Check if the old image exists in the file
    if ! grep -q "$old_image" "$job_file"; then
        echo "⚠️  Warning: Image '$old_image' not found in $job_file, skipping..."
        return
    fi
    
    # Perform the replacement
    sed -i "s|image = \"$old_image\"|image = \"$new_image\"|g" "$job_file"
    echo "✅ Updated $job_file: $old_image → $new_image"
}

# Update all job files
echo "🔧 Updating job files..."
for job_file in "${!JOB_MAPPINGS[@]}"; do
    update_job_file "$job_file" "${JOB_MAPPINGS[$job_file]}"
done

echo ""
echo "✅ All Nomad jobs updated to use GCR images!"
echo ""
echo "📋 Summary of changes:"
echo "   - All images now use: ${GCP_REGISTRY}/services/..."
echo "   - Backup created in: $BACKUP_DIR"
echo ""
echo "🚀 Next steps:"
echo "   1. Restart Nomad jobs: make restart-nomad"
echo "   2. Deploy updated jobs: nomad job run jobs/JOBNAME.nomad.hcl"
echo "   3. Verify no Docker pull errors in logs"
echo ""
echo "🔙 To revert changes:"
echo "   cp $BACKUP_DIR/* jobs/" 