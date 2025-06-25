# Vexa Makefile Cheat Sheet

## 🎯 Quick Start

**Complete Deployment Workflow:**
```bash
make                    # Build -> Push -> Deploy (CPU)
make TARGET=gpu         # Build -> Push -> Deploy (GPU)
```

## 📋 Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TAG` | `dev` | Docker image tag |
| `PREFIX` | `services` | Local image namespace (hardcoded) |
| `DOCKERHUB_USER` | `vexaai` | Docker Hub username |
| `TARGET` | `cpu` | Deployment target (`cpu`/`gpu` for WhisperLive) |

## 🔧 Main Workflow Commands

### Complete Workflows
```bash
make all                # Full workflow: build -> push -> deploy
make all TARGET=gpu     # Full workflow with GPU WhisperLive
```

### Individual Phases
```bash
make build             # Build all images locally
make push              # Build and push to Docker Hub
make deploy            # Deploy to Nomad with TARGET support
make deploy TARGET=gpu # Deploy with GPU WhisperLive
```

## 🐳 Building Services

### Build All Services
```bash
make build-all         # Build all services at once
```

### Individual Service Builds
```bash
make build-admin-api
make build-api-gateway
make build-vexa-bot
make build-bot-manager
make build-whisperlive-gpu
make build-whisperlive-cpu
make build-transcription-collector
```

## 🚀 Docker Hub Operations

### Push All Images
```bash
make push              # Build and push all to Docker Hub
```

### Individual Push Operations
```bash
make push-admin-api
make push-api-gateway
make push-vexa-bot
make push-bot-manager
make push-transcription-collector
make push-whisperlive-cpu
make push-whisperlive-gpu
```

## ⚡ Nomad Management

### Start/Stop Services
```bash
make nomad-start       # Start all Nomad jobs
make nomad-stop        # Stop all Nomad jobs
make nomad-restart     # Restart jobs (preserves TARGET)
```

### Full System Operations
```bash
make nomad-restart-full    # Stop jobs -> restart Nomad -> deploy with TARGET=cpu
make nomad-status         # Show job and service status
```

## 🔧 Configuration & Setup

```bash
make setup-nomad-vars     # Setup Nomad variables from vexa/.env
```

## 🛠 Utility Commands

### Image Management
```bash
make show-images          # Display locally built images
make clean               # Remove all local images with PREFIX namespace
```

### Help
```bash
make help                # Show detailed help with examples
```

## 📚 Service Architecture

The Makefile builds these services:

| Service | Purpose | Build Target |
|---------|---------|--------------|
| `admin-api` | Administrative API | `build-admin-api` |
| `api-gateway` | API Gateway | `build-api-gateway` |
| `vexa-bot` | Main bot service | `build-vexa-bot` |
| `bot-manager` | Bot management | `build-bot-manager` |
| `whisperlive-gpu` | GPU transcription | `build-whisperlive-gpu` |
| `whisperlive-cpu` | CPU transcription | `build-whisperlive-cpu` |
| `transcription-collector` | Transcription data | `build-transcription-collector` |

## 🎮 TARGET Support (GPU/CPU)

The `TARGET` variable controls WhisperLive deployment:

```bash
# CPU-only deployment (default)
make deploy TARGET=cpu
make nomad-start TARGET=cpu

# GPU-enabled deployment  
make deploy TARGET=gpu
make nomad-start TARGET=gpu
```

## 🔄 Common Workflows

### Development Cycle
```bash
# 1. Build and test locally
make build

# 2. Check built images
make show-images

# 3. Deploy locally for testing
make deploy TARGET=cpu

# 4. Push to production
make push
```

### Production Deployment
```bash
# Complete production deployment
make all TARGET=gpu

# Or step by step:
make build
make push  
make deploy TARGET=gpu
```

### Troubleshooting
```bash
# Check service status
make nomad-status

# Restart everything
make nomad-restart-full

# Clean and rebuild
make clean
make build
```

## 📂 File Dependencies

- `vexa/.env` - Environment configuration
- `./scripts/setup-nomad-variables.sh` - Variable setup script
- `./scripts/update-to-dockerhub.sh` - Docker Hub image updater
- `./scripts/start-all-jobs.sh` - Job starter script
- `./scripts/stop-all-jobs.sh` - Job stopper script

## 💡 Tips

1. **Always specify TARGET** when deploying to ensure correct WhisperLive variant
2. **Use `make clean`** to free disk space during development
3. **Check `make nomad-status`** after deployment to verify services
4. **Run `make setup-nomad-vars`** after changing `vexa/.env`
5. **Use `make nomad-restart-full`** for complete system reset

## 🔍 Image Naming Convention

- **Local builds**: `services/service-name:dev`
- **Docker Hub**: `vexaai/service-name:dev`
- **WhisperLive variants**: `whisperlive:cpu-dev` / `whisperlive:gpu-dev` 