# Vexa Deployment on Vultr Cloud

This directory contains Terraform configuration for deploying the Vexa application stack on Vultr Cloud using HashiCorp Nomad orchestration.

## Architecture Overview

The deployment creates a complete Nomad cluster with the following components:

### Infrastructure
- **VPC Network**: Isolated network with `10.0.0.0/16` CIDR
- **Load Balancer**: For Nomad UI and API access
- **Firewall Groups**: Security rules for cluster communication
- **SSH Keys**: Automated key generation and distribution

### Nomad Cluster
- **3 Nomad Servers**: Cluster management and job scheduling
- **2 Static Service Clients**: For redis, admin-api, bot-manager
- **3 Workload Clients**: For scalable vexa-bot instances
- **1 GPU Client**: For whisperlive-gpu processing

### Service Discovery Architecture

This deployment uses the **industry-standard Consul + Nomad pattern** for robust cluster formation:

#### Why Consul + Nomad?
- **Vultr Limitation**: Nomad's native cloud auto-join doesn't support Vultr
- **Industry Standard**: HashiCorp's recommended approach for clouds without native support
- **Scalability**: Avoids hardcoded IPs and manual cluster management
- **Reliability**: Automatic cluster formation and self-healing

#### How It Works
1. **Consul Servers**: Run on Nomad server instances, form cluster via Vultr tags
2. **Consul Clients**: Run on all instances, join cluster automatically
3. **Nomad Servers**: Join cluster via Consul service discovery
4. **Nomad Clients**: Join cluster via Consul service discovery

#### Configuration Pattern
```hcl
# Consul auto-join using Vultr tags
retry_join = ["provider=vultr tag_key=ConsulAutoJoin tag_value=auto-join"]

# Nomad join via Consul
server_join {
  retry_join = ["provider=consul address=127.0.0.1:8500"]
}
```

#### Instance Tagging
All instances are tagged with:
- `ConsulAutoJoin:auto-join` - Enables Consul auto-join
- `Role:nomad-server|nomad-client` - Role identification
- `NodeClass:workload|gpu` - Workload targeting

**⚠️ Important**: This pattern eliminates the need for hardcoded IPs. Future contributors should NOT implement IP-based retry_join configurations, as they are brittle and don't scale.

### Cost Estimate
- **Base Monthly Cost**: ~$269/month
- **Scaling Range**: $269-400/month depending on workload
- Breakdown:
  - 3 Servers: 3 × $48 = $144/month
  - 2 Static Clients: 2 × $48 = $96/month
  - 3 Workload Clients: 3 × $24 = $72/month
  - 1 GPU Client: 1 × $43 = $43/month
  - Load Balancer: $10/month

## Prerequisites

1. **Vultr Account**: Sign up at [vultr.com](https://www.vultr.com/) (get $250 free credit)
2. **API Key**: Generate at [my.vultr.com/settings/#settingsapi](https://my.vultr.com/settings/#settingsapi)
3. **Terraform**: Install from [terraform.io](https://terraform.io/downloads.html)
4. **Git**: For cloning the repository

## Quick Start

### 1. Clone and Configure

```bash
# Clone the repository
git clone <repository-url>
cd vexa-deployment/terraform/vultr

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit with your settings
nano terraform.tfvars
```

### 2. Set Required Variables

Edit `terraform.tfvars` and set:

```hcl
# Required: Your Vultr API key
vultr_api_key = "your_vultr_api_key_here"

# Optional: Adjust region, instance counts, etc.
region = "ewr"  # New Jersey
nomad_client_workload_count = 3  # Scale based on needs
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review deployment plan
terraform plan

# Deploy infrastructure (single command!)
terraform apply -auto-approve
```

### 4. Access Nomad UI

After deployment completes (5-10 minutes):

```bash
# Get the Nomad UI URL from output
terraform output nomad_ui_url

# Example: http://45.77.123.456:4646
```

## Automatic Job Deployment

**NEW**: The Vultr deployment now includes automatic deployment of all Vexa services from the `/jobs` directory!

### How It Works

The Terraform configuration automatically:
1. **Waits for Nomad cluster** to be ready
2. **Creates Nomad Variables** for database credentials and API tokens
3. **Deploys all 12 services** from the `/jobs` directory
4. **Configures service discovery** via Consul

### Complete Deployment

Instead of manually deploying jobs after infrastructure, you can now do everything in one command:

```bash
# Deploy infrastructure AND all jobs automatically
terraform apply -auto-approve

# Or use the deployment script
./deploy-jobs.sh
```

### Database Configuration

Before deploying, configure your external PostgreSQL database in `terraform.tfvars`:

```hcl
# Database Configuration for Nomad Jobs
db_host     = "your-db-host"      # External PostgreSQL host
db_port     = "5432"              # PostgreSQL port
db_name     = "vexa"              # Database name
db_user     = "postgres"          # Database user
db_password = "your-password"     # Database password
admin_api_token = "your-token"    # Admin API token
```

### Deployed Services

The following services are automatically deployed:

| Service | Purpose | Node Class |
|---------|---------|------------|
| `redis` | Cache and session storage | Static |
| `admin-api` | User management API | Static |
| `bot-manager` | Bot orchestration | Static |
| `api-gateway` | Request routing | Static |
| `transcription-collector` | Data processing | Static |
| `whisperlive-cpu` | Speech processing (CPU) | Workload |
| `whisperlive-gpu` | Speech processing (GPU) | GPU |
| `vexa-bot` | Meeting bot instances | Workload |
| `prometheus` | Metrics collection | Static |
| `nomad-autoscaler` | Auto-scaling | Static |
| `whisperlive-metrics-exporter` | Custom metrics | Static |
| `db-init` | Database initialization | Static |

### Verification

After deployment, verify all services are running:

```bash
# Check job status
terraform output deployed_jobs

# Access Nomad UI to monitor
terraform output nomad_ui_url

# Test API Gateway
curl http://$(terraform output -raw load_balancer_ip):8926/health
```

### Benefits

- **One-Click Deployment**: Infrastructure + services in single command
- **Secret Management**: Database credentials stored securely in Nomad Variables
- **No Manual Steps**: Eliminates post-deployment job registration
- **Infrastructure as Code**: Complete deployment defined in Terraform
- **Production Ready**: Includes monitoring, autoscaling, and load balancing

## Infrastructure Components

### Instance Types and Sizing

| Component | Plan | Specs | Monthly Cost | Use Case |
|-----------|------|-------|--------------|----------|
| Nomad Servers | `vhp-4c-8gb` | 4 vCPU, 8GB RAM, 180GB SSD | $48 | Cluster management |
| Static Clients | `vhp-4c-8gb` | 4 vCPU, 8GB RAM, 180GB SSD | $48 | Core services |
| Workload Clients | `vhp-2c-4gb` | 2 vCPU, 4GB RAM, 100GB SSD | $24 | Scalable apps |
| GPU Clients | `vcg-a16-2c-8g-50s-1gpu` | 2 vCPU, 8GB RAM, 50GB SSD, 2GB GPU | $43 | ML/AI workloads |

### Network Security

- **VPC Isolation**: All instances in private network
- **Firewall Rules**: 
  - SSH (22) from anywhere
  - Nomad HTTP (4646) from anywhere 
  - Nomad internal (4647, 4648) VPC only
  - Application ports (8000-9000) from anywhere
- **Load Balancer**: Health checks and traffic distribution

### Automation Features

- **Cloud-Init**: Fully automated Nomad installation
- **Service Discovery**: Automatic cluster formation
- **SSH Keys**: Generated and distributed automatically
- **DNS Resolution**: Internal hostname resolution
- **Docker**: Pre-installed with GPU support where needed

## Operational Procedures

### Scaling the Cluster

#### Add More Workload Clients

```bash
# Edit terraform.tfvars
nomad_client_workload_count = 5  # Increase from 3 to 5

# Apply changes
terraform apply
```

#### Add GPU Capacity

```bash
# Edit terraform.tfvars
nomad_client_gpu_count = 2  # Increase from 1 to 2

# Apply changes
terraform apply
```

### SSH Access

```bash
# Get SSH commands from Terraform output
terraform output ssh_command_servers
terraform output ssh_command_clients

# Use generated SSH key
ssh -i ssh-key-vexa-prod.pem root@<instance-ip>
```

### Monitoring Cluster Health

```bash
# SSH to any server node
ssh -i ssh-key-vexa-prod.pem root@<server-ip>

# Check server status
nomad server members

# Check client status
nomad node status

# Check running jobs
nomad job status
```

### Troubleshooting

#### Check Instance Status

```bash
# View all instances
terraform show | grep "vultr_instance"

# Check specific instance
terraform state show vultr_instance.nomad_servers[0]
```

#### View Cloud-Init Logs

```bash
# SSH to problematic instance
ssh -i ssh-key-vexa-prod.pem root@<instance-ip>

# Check cloud-init status
cloud-init status

# View cloud-init logs
sudo tail -f /var/log/cloud-init-output.log

# Check Nomad service
sudo systemctl status nomad
sudo journalctl -u nomad -f
```

#### Network Connectivity Issues

```bash
# Test VPC connectivity
ping <other-instance-private-ip>

# Check firewall rules
sudo ufw status

# Test Nomad ports
telnet <server-private-ip> 4647
```

### Backup and Recovery

#### Backup Nomad State

```bash
# SSH to leader server
nomad server members | grep "true"

# Create backup (automatic via Raft)
nomad operator snapshot save backup.snap
```

#### Destroy and Recreate

```bash
# Destroy everything
terraform destroy

# Recreate from scratch
terraform apply
```

## File Structure

```
vultr/
├── main.tf                    # Main infrastructure resources
├── variables.tf               # Variable definitions
├── outputs.tf                 # Output definitions
├── providers.tf               # Provider configuration
├── cloud-init-server.tpl     # Server node configuration
├── cloud-init-client.tpl     # Client node configuration
├── terraform.tfvars.example  # Example configuration
├── README.md                  # This file
└── ssh-key-*.pem             # Generated SSH key (created after apply)
```

## Phase 2: Job Deployment

After infrastructure is ready, Phase 2 will add:

1. **Nomad Job Definitions**: Terraform resources for deploying jobs
2. **Service Templates**: Parameterized job configurations
3. **Health Checks**: Application-level monitoring
4. **Load Balancing**: Service discovery and routing

## Security Considerations

### Production Hardening

1. **Restrict SSH Access**: Update `allowed_ssh_cidr` to your IP range
2. **Enable TLS**: Configure Nomad with TLS certificates
3. **Enable ACLs**: Set up Nomad Access Control Lists
4. **VPN Access**: Consider VPN for admin access
5. **Regular Updates**: Keep Nomad and OS packages updated

### Secrets Management

- Use Nomad Variables for sensitive data
- Consider HashiCorp Vault integration
- Rotate SSH keys regularly

## Support and Resources

- **Vultr Documentation**: [docs.vultr.com](https://docs.vultr.com/)
- **Nomad Documentation**: [nomadproject.io](https://www.nomadproject.io/)
- **Terraform Vultr Provider**: [registry.terraform.io/providers/vultr/vultr](https://registry.terraform.io/providers/vultr/vultr)

## Next Steps

1. ✅ **Phase 1 Complete**: Infrastructure deployment
2. 🔄 **Phase 2**: Deploy Nomad jobs (redis, admin-api, etc.)
3. 📊 **Phase 3**: Add monitoring and alerting
4. 🔒 **Phase 4**: Security hardening and production readiness 