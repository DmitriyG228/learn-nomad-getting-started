#!/bin/bash

# Vultr Vexa Deployment Script with Job Deployment
# This script deploys the complete Vexa platform to Vultr with automatic job deployment

set -e

echo "🚀 Vultr Vexa Deployment with Job Deployment"
echo "=============================================="

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo "❌ terraform.tfvars not found!"
    echo "Please copy terraform.tfvars.example to terraform.tfvars and configure your settings:"
    echo "  cp terraform.tfvars.example terraform.tfvars"
    echo "  # Edit terraform.tfvars with your Vultr API key and database configuration"
    exit 1
fi

# Check if VULTR_API_KEY is set
if ! grep -q "VULTR_API_KEY" terraform.tfvars; then
    echo "❌ VULTR_API_KEY not found in terraform.tfvars!"
    echo "Please add your Vultr API key to terraform.tfvars:"
    echo "  VULTR_API_KEY = \"your-api-key-here\""
    exit 1
fi

# Check if database configuration is set
if ! grep -q "db_host" terraform.tfvars; then
    echo "⚠️  Database configuration not found in terraform.tfvars!"
    echo "Please add database configuration to terraform.tfvars:"
    echo "  db_host     = \"your-db-host\""
    echo "  db_port     = \"your-db-port\""
    echo "  db_name     = \"your-db-name\""
    echo "  db_user     = \"your-db-user\""
    echo "  db_password = \"your-db-password\""
    echo "  admin_api_token = \"your-admin-token\""
    echo ""
    echo "Continuing with default values..."
fi

echo "✅ Configuration validated"
echo ""

# Initialize Terraform
echo "🔧 Initializing Terraform..."
terraform init

# Plan the deployment
echo "📋 Planning deployment..."
terraform plan

echo ""
echo "⚠️  This will deploy:"
echo "   - ${nomad_server_count:-3} Nomad server instances"
echo "   - ${nomad_client_static_count:-2} static client instances"
echo "   - ${nomad_client_workload_count:-3} workload client instances"
echo "   - ${nomad_client_gpu_count:-1} GPU client instances"
echo "   - Load balancer for Nomad UI"
echo "   - All 12 Vexa services from /jobs directory"
echo ""

read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Deployment cancelled"
    exit 1
fi

# Apply the deployment
echo "🚀 Deploying infrastructure and jobs..."
terraform apply -auto-approve

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📊 Deployment Summary:"
terraform output deployment_summary

echo ""
echo "🔗 Access Points:"
echo "   - Nomad UI: $(terraform output -raw nomad_ui_url)"
echo "   - Load Balancer IP: $(terraform output -raw load_balancer_ip)"

echo ""
echo "📋 Deployed Jobs:"
terraform output deployed_jobs

echo ""
echo "🔧 Next Steps:"
echo "   1. Access Nomad UI to monitor job status"
echo "   2. Check service health: nomad job status"
echo "   3. View logs: nomad logs -f <allocation-id>"
echo "   4. Test API Gateway: curl http://$(terraform output -raw load_balancer_ip):8926/health"

echo ""
echo "🎉 Vexa platform is now running on Vultr!" 