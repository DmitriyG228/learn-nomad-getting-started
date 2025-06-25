# Vexa Nomad Development Makefile
# Complete workflow: Build -> Push -> Deploy with CPU/GPU target support

TAG ?= dev
PREFIX := services
DOCKERHUB_USER ?= vexaai
TARGET ?= cpu

.PHONY: all build build-all push deploy setup-nomad-vars nomad-restart-full clean show-images nomad-start nomad-stop nomad-restart nomad-status help

# Default target: Complete workflow
all: build push deploy
	@echo ""
	@echo "🎉 Complete workflow finished!"
	@echo "📋 TARGET=$(TARGET) - All images built, pushed, and deployed successfully"

# Build all services locally
build: build-all
	@echo "✅ All images built and available locally for Nomad with tag $(TAG)"

build-all: build-admin-api build-api-gateway build-vexa-bot build-bot-manager build-whisperlive-gpu build-whisperlive-cpu build-transcription-collector
	@echo "✅ All services built successfully"

build-admin-api:
	@echo "📦 Building admin-api..."
	docker build -t $(PREFIX)/admin-api:$(TAG) -f vexa/services/admin-api/Dockerfile vexa

build-api-gateway:
	@echo "📦 Building api-gateway..."
	docker build -t $(PREFIX)/api-gateway:$(TAG) -f vexa/services/api-gateway/Dockerfile vexa

build-vexa-bot:
	@echo "📦 Building vexa-bot..."
	docker build -t $(PREFIX)/vexa-bot:$(TAG) vexa/services/vexa-bot/core

build-bot-manager:
	@echo "📦 Building bot-manager..."
	docker build -t $(PREFIX)/bot-manager:$(TAG) -f vexa/services/bot-manager/Dockerfile vexa

build-whisperlive-gpu:
	@echo "📦 Building WhisperLive GPU..."
	docker build -t $(PREFIX)/whisperlive:gpu-$(TAG) -f vexa/services/WhisperLive/Dockerfile.project vexa

build-whisperlive-cpu:
	@echo "📦 Building WhisperLive CPU..."
	docker build -t $(PREFIX)/whisperlive:cpu-$(TAG) -f vexa/services/WhisperLive/Dockerfile.cpu vexa

build-transcription-collector:
	@echo "📦 Building transcription-collector..."
	docker build -t $(PREFIX)/transcription-collector:$(TAG) -f vexa/services/transcription-collector/Dockerfile vexa

# Push all images to Docker Hub
push: build-all
	@echo "🚀 Pushing all images to Docker Hub: $(DOCKERHUB_USER)"
	@docker login
	@$(MAKE) push-admin-api
	@$(MAKE) push-api-gateway
	@$(MAKE) push-vexa-bot
	@$(MAKE) push-bot-manager
	@$(MAKE) push-transcription-collector
	@$(MAKE) push-whisperlive-cpu
	@$(MAKE) push-whisperlive-gpu
	@echo "✅ All images pushed to Docker Hub successfully!"

push-admin-api:
	@echo "📤 Pushing admin-api..."
	docker tag $(PREFIX)/admin-api:$(TAG) $(DOCKERHUB_USER)/admin-api:$(TAG)
	docker push $(DOCKERHUB_USER)/admin-api:$(TAG)

push-api-gateway:
	@echo "📤 Pushing api-gateway..."
	docker tag $(PREFIX)/api-gateway:$(TAG) $(DOCKERHUB_USER)/api-gateway:$(TAG)
	docker push $(DOCKERHUB_USER)/api-gateway:$(TAG)

push-vexa-bot:
	@echo "📤 Pushing vexa-bot..."
	docker tag $(PREFIX)/vexa-bot:$(TAG) $(DOCKERHUB_USER)/vexa-bot:$(TAG)
	docker push $(DOCKERHUB_USER)/vexa-bot:$(TAG)

push-bot-manager:
	@echo "📤 Pushing bot-manager..."
	docker tag $(PREFIX)/bot-manager:$(TAG) $(DOCKERHUB_USER)/bot-manager:$(TAG)
	docker push $(DOCKERHUB_USER)/bot-manager:$(TAG)

push-transcription-collector:
	@echo "📤 Pushing transcription-collector..."
	docker tag $(PREFIX)/transcription-collector:$(TAG) $(DOCKERHUB_USER)/transcription-collector:$(TAG)
	docker push $(DOCKERHUB_USER)/transcription-collector:$(TAG)

push-whisperlive-cpu:
	@echo "📤 Pushing WhisperLive CPU..."
	docker tag $(PREFIX)/whisperlive:cpu-$(TAG) $(DOCKERHUB_USER)/whisperlive:cpu-$(TAG)
	docker push $(DOCKERHUB_USER)/whisperlive:cpu-$(TAG)

push-whisperlive-gpu:
	@echo "📤 Pushing WhisperLive GPU..."
	docker tag $(PREFIX)/whisperlive:gpu-$(TAG) $(DOCKERHUB_USER)/whisperlive:gpu-$(TAG)
	docker push $(DOCKERHUB_USER)/whisperlive:gpu-$(TAG)

# Setup Nomad Variables from environment configuration
setup-nomad-vars:
	@echo "🔧 Setting up Nomad Variables from vexa/.env..."
	@./scripts/setup-nomad-variables.sh

# Deploy with TARGET support (cpu/gpu for WhisperLive)
deploy:
	@echo "🔄 Updating Nomad job files to use Docker Hub images..."
	@./scripts/update-to-dockerhub.sh
	@$(MAKE) setup-nomad-vars
	@echo "🚀 Starting services with TARGET=$(TARGET)..."
	@if [ "$(TARGET)" = "gpu" ]; then \
		echo "🎮 Deploying GPU-enabled WhisperLive services"; \
		TARGET=gpu $(MAKE) nomad-start; \
	else \
		echo "💻 Deploying CPU-only WhisperLive services"; \
		TARGET=cpu $(MAKE) nomad-start; \
	fi
	@echo ""
	@echo "✅ Deployment complete with TARGET=$(TARGET)"

# Nomad Job Management with TARGET support
nomad-start:
	@echo "🚀 Starting Nomad jobs with TARGET=$(TARGET)..."
	@TARGET=$(TARGET) ./scripts/start-all-jobs.sh

nomad-stop:
	@echo "🛑 Stopping all Nomad jobs..."
	@./scripts/stop-all-jobs.sh

nomad-restart: nomad-stop
	@echo "⏳ Waiting 5 seconds for jobs to stop..."
	@sleep 5
	@$(MAKE) nomad-start TARGET=$(TARGET)

# Complete restart: Stop jobs, restart Nomad, deploy with default TARGET=cpu
nomad-restart-full: nomad-stop
	@echo "🔄 Restarting Nomad service..."
	@sudo systemctl restart nomad
	@echo "⏳ Waiting 10 seconds for Nomad to start..."
	@sleep 10
	@echo "🚀 Running complete deployment with TARGET=cpu..."
	@$(MAKE) all TARGET=cpu

nomad-status:
	@echo "📊 Nomad jobs status:"
	@nomad job status
	@echo ""
	@echo "📊 Service discovery status:"
	@nomad service list || echo "No services registered"

# Utility targets
show-images:
	@echo "📋 Locally built images:"
	@docker images $(PREFIX)/*:$(TAG) --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}'

clean:
	@echo "🧹 Removing locally built images..."
	docker image ls $(PREFIX)/*:$(TAG) --format '{{.Repository}}:{{.Tag}}' | xargs -r docker rmi -f || true
	@echo "✅ Cleanup complete"

# Help
help:
	@echo "Vexa Nomad Development Makefile"
	@echo "================================"
	@echo ""
	@echo "Main workflow:"
	@echo "  all               - Complete workflow: build -> push -> deploy"
	@echo "  build             - Build all images locally"
	@echo "  push              - Build and push all images to Docker Hub"
	@echo "  deploy            - Deploy with TARGET support (cpu/gpu)"
	@echo ""
	@echo "Nomad management:"
	@echo "  nomad-start       - Start jobs with TARGET support"
	@echo "  nomad-stop        - Stop all Nomad jobs"
	@echo "  nomad-restart     - Restart jobs with current TARGET"
	@echo "  nomad-restart-full - Stop jobs, restart Nomad service, deploy with TARGET=cpu"
	@echo "  nomad-status      - Show status of all jobs"
	@echo ""
	@echo "Configuration:"
	@echo "  setup-nomad-vars  - Setup Nomad Variables from vexa/.env"
	@echo ""
	@echo "Utilities:"
	@echo "  show-images       - Show locally built images"
	@echo "  clean             - Remove local images"
	@echo "  help              - Show this help"
	@echo ""
	@echo "Examples:"
	@echo "  make               # Complete workflow with CPU (default)"
	@echo "  make all           # Same as above"
	@echo "  make all TARGET=gpu # Complete workflow with GPU WhisperLive"
	@echo "  make deploy TARGET=cpu # Deploy CPU version only"
	@echo "  make nomad-restart-full # Full restart with Nomad service restart"
	@echo ""
	@echo "Configuration:"
	@echo "  TAG=$(TAG)"
	@echo "  TARGET=$(TARGET) (cpu/gpu for WhisperLive deployment)"
	@echo "  DOCKERHUB_USER=$(DOCKERHUB_USER)" 