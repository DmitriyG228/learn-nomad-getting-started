#!/bin/bash

# Vexa Vultr Deployment Script
# This script automates the deployment of the Vexa stack on Vultr Cloud

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions for colored output
error() { echo -e "${RED}ERROR: $1${NC}" >&2; }
success() { echo -e "${GREEN}SUCCESS: $1${NC}"; }
warning() { echo -e "${YELLOW}WARNING: $1${NC}"; }
info() { echo -e "${BLUE}INFO: $1${NC}"; }

# Check if we're in the correct directory
if [ ! -f "main.tf" ] || [ ! -f "providers.tf" ]; then
    error "Please run this script from the vexa-deployment/terraform/vultr directory"
    exit 1
fi

info "Starting Vexa Vultr Deployment..."

# Check prerequisites
info "Checking prerequisites..."

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    error "Terraform is not installed. Please install from https://terraform.io/downloads.html"
    exit 1
fi

# Check Terraform version
TERRAFORM_VERSION=$(terraform version -json | jq -r '.terraform_version')
info "Found Terraform version: $TERRAFORM_VERSION"

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    warning "terraform.tfvars not found. Creating from example..."
    if [ -f "terraform.tfvars.example" ]; then
        cp terraform.tfvars.example terraform.tfvars
        warning "Please edit terraform.tfvars and set your Vultr API key:"
        echo "  vultr_api_key = \"your_vultr_api_key_here\""
        echo ""
        echo "Get your API key from: https://my.vultr.com/settings/#settingsapi"
        echo ""
        read -p "Press Enter after you've updated terraform.tfvars..."
    else
        error "terraform.tfvars.example not found"
        exit 1
    fi
fi

# Check if API key is set
if grep -q "YOUR_VULTR_API_KEY_HERE" terraform.tfvars; then
    error "Please set your Vultr API key in terraform.tfvars"
    exit 1
fi

# Initialize Terraform
info "Initializing Terraform..."
terraform init

# Validate configuration
info "Validating Terraform configuration..."
terraform validate

# Show deployment plan
info "Generating deployment plan..."
terraform plan -out=tfplan

# Ask for confirmation
echo ""
warning "This will create infrastructure on Vultr Cloud which will incur costs."
warning "Estimated monthly cost: ~\$269-400 depending on configuration"
echo ""
read -p "Do you want to proceed with deployment? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    info "Deployment cancelled."
    exit 0
fi

# Apply the plan
info "Deploying infrastructure... This may take 5-10 minutes."
terraform apply tfplan

# Check if deployment succeeded
if [ $? -eq 0 ]; then
    success "Infrastructure deployment completed!"
    echo ""
    info "Getting deployment information..."
    
    # Show important outputs
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    terraform output deployment_summary
    
    echo ""
    echo "=== NOMAD UI ACCESS ==="
    echo "Nomad UI URL: $(terraform output -raw nomad_ui_url)"
    
    echo ""
    echo "=== SSH ACCESS ==="
    info "SSH private key saved as: $(ls ssh-key-*.pem)"
    echo "Server SSH commands:"
    terraform output -json ssh_command_servers | jq -r '.[]'
    
    echo ""
    echo "=== NEXT STEPS ==="
    terraform output -json next_steps | jq -r '.[]'
    
    echo ""
    success "Deployment completed successfully!"
    info "Check the Nomad UI to verify cluster health: $(terraform output -raw nomad_ui_url)"
    
else
    error "Deployment failed. Check the error messages above."
    exit 1
fi

# Cleanup
rm -f tfplan

info "Deployment script completed." 