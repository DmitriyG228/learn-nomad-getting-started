#!/bin/bash

# Setup Nomad Variables from environment configuration
# This ensures variables are recreated after Nomad restarts
# FAILS FAST if required variables are not set - no fallbacks

set -e

echo "🔧 Setting up Nomad Variables..."

# Source environment file - REQUIRED
if [ -f "vexa/.env" ]; then
    echo "📄 Loading variables from vexa/.env"
    source vexa/.env
else
    echo "❌ ERROR: vexa/.env file not found!"
    echo "   Create vexa/.env with required database and API configuration"
    exit 1
fi

# Validate all required variables are set - NO FALLBACKS
required_vars=("DB_HOST" "DB_PORT" "DB_NAME" "DB_USER" "DB_PASSWORD" "ADMIN_API_TOKEN")
missing_vars=()

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        missing_vars+=("$var")
    fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
    echo "❌ ERROR: Missing required environment variables:"
    for var in "${missing_vars[@]}"; do
        echo "   - $var"
    done
    echo ""
    echo "   Add these variables to vexa/.env file"
    exit 1
fi

echo "🗃️  Creating Nomad Variable: secret/vexa/db"
nomad var put -force secret/vexa/db \
    host="$DB_HOST" \
    port="$DB_PORT" \
    name="$DB_NAME" \
    user="$DB_USER" \
    password="$DB_PASSWORD"

echo "🔑 Creating Nomad Variable: secret/vexa/admin-api"
nomad var put -force secret/vexa/admin-api \
    token="$ADMIN_API_TOKEN"

echo "✅ Nomad Variables created successfully!"

# Verify variables were created
echo ""
echo "📋 Current Nomad Variables:"
nomad var list

echo ""
echo "🔍 Verifying variable contents:"
echo "Database config:"
nomad var get secret/vexa/db
echo ""
echo "Admin API config:"
nomad var get secret/vexa/admin-api

echo ""
echo "✅ Nomad Variables setup complete!" 