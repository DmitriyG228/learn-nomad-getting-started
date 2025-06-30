# 🚀 Vexa Vultr Deployment Guide

**Single Command Deployment for Vultr Cloud - Phase 1 Complete**

## ⚡ Quick Deploy (2 minutes)

```bash
# 1. Navigate to directory
cd vexa-deployment/terraform/vultr

# 2. Run automated deployment script
./deploy.sh
```

That's it! The script will guide you through the process.

## 📋 Prerequisites Checklist

- [ ] **Vultr Account**: [Sign up](https://www.vultr.com/) (get $250 free credit)
- [ ] **API Key**: Generate at [Vultr API Settings](https://my.vultr.com/settings/#settingsapi)
- [ ] **Terraform**: Install from [terraform.io](https://terraform.io/downloads.html)

## 🎯 What Gets Deployed

| Component | Count | Specs | Monthly Cost |
|-----------|-------|-------|--------------|
| **Nomad Servers** | 3 | 4 vCPU, 8GB RAM | $144 |
| **Static Clients** | 2 | 4 vCPU, 8GB RAM | $96 |
| **Workload Clients** | 3 | 2 vCPU, 4GB RAM | $72 |
| **GPU Clients** | 1 | A16 1/8 GPU | $43 |
| **Load Balancer** | 1 | Small | $10 |
| **Total** | **10 instances** | **Auto-configured** | **~$365/month** |

## 🔧 Manual Deployment (if preferred)

```bash
# 1. Copy configuration template
cp terraform.tfvars.example terraform.tfvars

# 2. Edit with your API key
nano terraform.tfvars
# Set: vultr_api_key = "your_api_key_here"

# 3. Deploy infrastructure
terraform init
terraform plan
terraform apply -auto-approve
```

## 📊 After Deployment

### Access Nomad UI
```bash
# Get URL from output
terraform output nomad_ui_url
# Example: http://45.77.123.456:4646
```

### SSH to Instances
```bash
# View SSH commands
terraform output ssh_command_servers
terraform output ssh_command_clients

# Example SSH
ssh -i ssh-key-vexa-prod.pem root@<ip-address>
```

### Verify Cluster Health
```bash
# SSH to any server and run:
nomad server members  # Check server status
nomad node status     # Check client status
```

## 🎯 Next Steps (Phase 2)

After infrastructure is running:

1. **Deploy Jobs**: redis, admin-api, bot-manager
2. **Configure Services**: Set up service discovery
3. **Scale Testing**: Verify vexa-bot autoscaling
4. **GPU Workloads**: Deploy whisperlive-gpu

## 🚨 Troubleshooting

### Common Issues

**Terraform errors**:
```bash
# Reinitialize if needed
terraform init -upgrade
```

**Instance not accessible**:
```bash
# Check cloud-init logs
sudo tail -f /var/log/cloud-init-output.log
```

**Nomad not starting**:
```bash
# Check service status
sudo systemctl status nomad
sudo journalctl -u nomad -f
```

### Cost Management

**Monitor spending**:
- Vultr Dashboard → Billing
- Expected: ~$365/month for full setup

**Scale down for testing**:
```hcl
# In terraform.tfvars
nomad_client_workload_count = 1  # Reduce from 3 to 1
nomad_client_gpu_count = 0       # Disable GPU for testing
```

## 📁 File Structure

```
vultr/
├── 🚀 deploy.sh              # Automated deployment script
├── 📖 README.md             # Detailed documentation
├── ⚡ DEPLOYMENT_GUIDE.md   # This quick guide
├── 🔧 main.tf               # Infrastructure resources
├── 📝 variables.tf          # Configuration variables
├── 📤 outputs.tf            # Deployment outputs
├── 🔌 providers.tf          # Terraform providers
├── 🖥️  cloud-init-server.tpl # Server configuration
├── 💻 cloud-init-client.tpl # Client configuration
└── 📋 terraform.tfvars.example
```

## ✅ Success Criteria

- [ ] Nomad UI accessible at load balancer IP
- [ ] All servers show "alive" status
- [ ] All clients show "ready" status
- [ ] SSH access works to all instances
- [ ] GPU instances have NVIDIA drivers installed

## 🆘 Support

- **Documentation**: [README.md](./README.md) for detailed info
- **Vultr Support**: [docs.vultr.com](https://docs.vultr.com/)
- **Nomad Docs**: [nomadproject.io](https://www.nomadproject.io/)

---

**Phase 1 Status**: ✅ **COMPLETE** - Ready for testing and Phase 2 development 