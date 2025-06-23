#!/bin/bash

# Script to update all Nomad job files to use Docker Hub images
# It replaces GCR or local service URLs with the specified Docker Hub user's repo.
# Usage: ./scripts/update-to-dockerhub.sh

set -e

# Configuration
GCP_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "not-configured")
GCP_REGISTRY="gcr.io/${GCP_PROJECT}"
DOCKERHUB_USER=${DOCKERHUB_USER:-vexaai}
TAG=${TAG:-dev}

echo "🔄 Updating Nomad jobs to use Docker Hub images..."
echo "📍 Docker Hub User: ${DOCKERHUB_USER}"
echo "📍 Tag: ${TAG}"
echo "--------------------------------------------------"

# Create backup directory
BACKUP_DIR="jobs/backup-dockerhub-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
echo "📁 Creating backup in: $BACKUP_DIR"
echo ""

# Find all .nomad.hcl files in the jobs directory
JOB_FILES=$(find jobs -maxdepth 1 -type f -name "*.nomad.hcl")

for job_file in $JOB_FILES; do
    echo "🔎 Processing $job_file..."

    # Create a backup before modifying
    cp "$job_file" "$BACKUP_DIR/"

    # Check if the file contains an image definition
    if ! grep -q 'image = ' "$job_file"; then
        echo "   -> No 'image' definition found. Skipping."
        continue
    fi

    # Replace gcr.io paths first
    sed -i -E "s|image = \"${GCP_REGISTRY}/services/([a-zA-Z0-9-]+):([a-zA-Z0-9-]+)\"|image = \"${DOCKERHUB_USER}/\1:\2\"|g" "$job_file"

    # Then replace local 'services/' paths
    sed -i -E "s|image = \"services/([a-zA-Z0-9-]+):([a-zA-Z0-9-]+)\"|image = \"${DOCKERHUB_USER}/\1:\2\"|g" "$job_file"

    echo "   ✅ Updated to use Docker Hub images."
done

echo ""
echo "✅ All Nomad jobs updated to use Docker Hub images!"
echo ""
echo "📋 Summary of changes:"
echo "   - All images now reference: ${DOCKERHUB_USER}/..."
echo "   - Backup created in: $BACKUP_DIR"
echo ""
echo "🚀 Next steps:"
echo "   1. Deploy updated jobs: nomad job run jobs/JOBNAME.nomad.hcl"
echo "   2. Verify that Nomad pulls the public images from Docker Hub."
echo ""
echo "🔙 To revert changes:"
echo "   cp $BACKUP_DIR/* jobs/" 