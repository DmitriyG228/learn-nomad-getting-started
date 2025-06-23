# Root Makefile to build local :dev images for Nomad development

TAG ?= dev
PREFIX ?= services
LOCAL_REGISTRY ?= localhost:5000

# GCP Container Registry Configuration
GCP_PROJECT ?= $(shell gcloud config get-value project 2>/dev/null)
GCP_REGISTRY ?= gcr.io/$(GCP_PROJECT)
GCP_REGION ?= us-central1

# Docker Hub Configuration
DOCKERHUB_USER ?= vexaai

.PHONY: build build-all build-admin-api build-api-gateway build-vexa-bot build-bot-manager build-whisperlive-gpu build-whisperlive-cpu build-transcription-collector build-json-debug clean start-registry stop-registry push-local clean-registry registry-ls push-gcr auth-gcr push-dockerhub deploy-dockerhub

# Default target builds all images and makes them available locally
build: build-all
	@echo "All images built and available locally for Nomad with tag $(TAG)"

# Build all services from docker-compose.yml
build-all: build-admin-api build-api-gateway build-vexa-bot build-bot-manager build-whisperlive-gpu build-whisperlive-cpu build-transcription-collector build-json-debug
	@echo "All services built successfully"

build-admin-api:
	@echo "Building admin-api from vexa/services/admin-api"
	docker build -t $(PREFIX)/admin-api:$(TAG) -f vexa/services/admin-api/Dockerfile vexa

build-api-gateway:
	@echo "Building api-gateway from vexa/services/api-gateway"
	docker build -t $(PREFIX)/api-gateway:$(TAG) -f vexa/services/api-gateway/Dockerfile vexa

build-vexa-bot:
	@echo "Building vexa-bot from vexa/services/vexa-bot/core"
	docker build -t $(PREFIX)/vexa-bot:$(TAG) vexa/services/vexa-bot/core

build-bot-manager:
	@echo "Building bot-manager from vexa/services/bot-manager"
	docker build -t $(PREFIX)/bot-manager:$(TAG) -f vexa/services/bot-manager/Dockerfile vexa

build-whisperlive-gpu:
	@echo "Building WhisperLive GPU image from vexa/services/WhisperLive"
	docker build -t $(PREFIX)/whisperlive:gpu-$(TAG) -f vexa/services/WhisperLive/Dockerfile.project vexa

build-whisperlive-cpu:
	@echo "Building WhisperLive CPU image from vexa/services/WhisperLive"
	docker build -t $(PREFIX)/whisperlive:cpu-$(TAG) -f vexa/services/WhisperLive/Dockerfile.cpu vexa

build-transcription-collector:
	@echo "Building transcription-collector from vexa/services/transcription-collector"
	docker build -t $(PREFIX)/transcription-collector:$(TAG) -f vexa/services/transcription-collector/Dockerfile vexa

build-json-debug:
	@echo "Building json-debug harness"
	docker build -t $(PREFIX)/json-debug:$(TAG) debug-json

# Local Docker Registry Management
start-registry:
	@echo "Starting local Docker registry on port 5000"
	@if [ ! "$$(docker ps -q -f name=local-registry)" ]; then \
		if [ "$$(docker ps -aq -f name=local-registry)" ]; then \
			docker rm local-registry; \
		fi; \
		docker run -d -p 5000:5000 --name local-registry registry:2.7; \
		echo "Local registry started at $(LOCAL_REGISTRY)"; \
		echo "Configure Docker daemon with: \"insecure-registries\": [\"$(LOCAL_REGISTRY)\"]"; \
	else \
		echo "Local registry already running"; \
	fi

stop-registry:
	@echo "Stopping local Docker registry"
	@docker stop local-registry 2>/dev/null || true
	@docker rm local-registry 2>/dev/null || true

# Push images to local registry (optional for multi-node setups)
push-local: start-registry build-all
	@echo "Pushing all images to local registry $(LOCAL_REGISTRY)"
	@$(MAKE) push-local-admin-api
	@$(MAKE) push-local-api-gateway
	@$(MAKE) push-local-vexa-bot
	@$(MAKE) push-local-bot-manager  
	@$(MAKE) push-local-transcription-collector
	@$(MAKE) push-local-whisperlive-cpu
	@$(MAKE) push-local-whisperlive-gpu

push-local-admin-api:
	@echo "Tagging and pushing admin-api to local registry"
	docker tag $(PREFIX)/admin-api:$(TAG) $(LOCAL_REGISTRY)/$(PREFIX)/admin-api:$(TAG)
	docker push $(LOCAL_REGISTRY)/$(PREFIX)/admin-api:$(TAG)

push-local-api-gateway:
	@echo "Tagging and pushing api-gateway to local registry"
	docker tag $(PREFIX)/api-gateway:$(TAG) $(LOCAL_REGISTRY)/$(PREFIX)/api-gateway:$(TAG)
	docker push $(LOCAL_REGISTRY)/$(PREFIX)/api-gateway:$(TAG)

push-local-vexa-bot:
	@echo "Tagging and pushing vexa-bot to local registry"
	docker tag $(PREFIX)/vexa-bot:$(TAG) $(LOCAL_REGISTRY)/$(PREFIX)/vexa-bot:$(TAG)
	docker push $(LOCAL_REGISTRY)/$(PREFIX)/vexa-bot:$(TAG)

push-local-bot-manager:
	@echo "Tagging and pushing bot-manager to local registry"
	docker tag $(PREFIX)/bot-manager:$(TAG) $(LOCAL_REGISTRY)/$(PREFIX)/bot-manager:$(TAG)
	docker push $(LOCAL_REGISTRY)/$(PREFIX)/bot-manager:$(TAG)

push-local-transcription-collector:
	@echo "Tagging and pushing transcription-collector to local registry"
	docker tag $(PREFIX)/transcription-collector:$(TAG) $(LOCAL_REGISTRY)/$(PREFIX)/transcription-collector:$(TAG)
	docker push $(LOCAL_REGISTRY)/$(PREFIX)/transcription-collector:$(TAG)

push-local-whisperlive-cpu:
	@echo "Tagging and pushing WhisperLive CPU to local registry"
	docker tag $(PREFIX)/whisperlive:cpu-$(TAG) $(LOCAL_REGISTRY)/$(PREFIX)/whisperlive:cpu-$(TAG)
	docker push $(LOCAL_REGISTRY)/$(PREFIX)/whisperlive:cpu-$(TAG)

push-local-whisperlive-gpu:
	@echo "Tagging and pushing WhisperLive GPU to local registry"
	docker tag $(PREFIX)/whisperlive:gpu-$(TAG) $(LOCAL_REGISTRY)/$(PREFIX)/whisperlive:gpu-$(TAG)
	docker push $(LOCAL_REGISTRY)/$(PREFIX)/whisperlive:gpu-$(TAG)

# Show local registry contents
registry-ls:
	@echo "Images in local registry:"
	@curl -s http://$(LOCAL_REGISTRY)/v2/_catalog 2>/dev/null | jq -r '.repositories[]' 2>/dev/null || echo "Registry not accessible (use: make start-registry)"

clean-registry: stop-registry
	@echo "Removing registry images from local Docker"
	@docker images $(LOCAL_REGISTRY)/$(PREFIX)/* --format '{{.Repository}}:{{.Tag}}' | xargs -r docker rmi -f || true

clean:
	@echo "Removing locally built images"
	docker image ls $(PREFIX)/*:$(TAG) --format '{{.Repository}}:{{.Tag}}' | xargs -r docker rmi -f || true

# Show all locally built images
show-images:
	@echo "Locally built images available for Nomad:"
	@docker images $(PREFIX)/*:$(TAG) --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}' 

# GCP Container Registry Management
auth-gcr:
	@echo "Configuring Docker authentication for GCP Container Registry"
	@gcloud auth configure-docker --quiet
	@echo "Authentication configured for GCR: $(GCP_REGISTRY)"

# Push all images to GCP Container Registry
push-gcr: auth-gcr build-all
	@echo "Pushing all images to GCP Container Registry: $(GCP_REGISTRY)"
	@if [ -z "$(GCP_PROJECT)" ]; then \
		echo "ERROR: GCP project not configured. Run: gcloud config set project YOUR_PROJECT_ID"; \
		exit 1; \
	fi
	@$(MAKE) push-gcr-admin-api
	@$(MAKE) push-gcr-api-gateway
	@$(MAKE) push-gcr-vexa-bot
	@$(MAKE) push-gcr-bot-manager  
	@$(MAKE) push-gcr-transcription-collector
	@$(MAKE) push-gcr-whisperlive-cpu
	@$(MAKE) push-gcr-whisperlive-gpu
	@echo "✅ All images pushed to GCR successfully!"
	@echo ""
	@echo "📋 To use GCR images in Nomad jobs, update image references:"
	@echo "   $(GCP_REGISTRY)/$(PREFIX)/admin-api:$(TAG)"
	@echo "   $(GCP_REGISTRY)/$(PREFIX)/api-gateway:$(TAG)"
	@echo "   $(GCP_REGISTRY)/$(PREFIX)/vexa-bot:$(TAG)"
	@echo "   $(GCP_REGISTRY)/$(PREFIX)/bot-manager:$(TAG)"
	@echo "   $(GCP_REGISTRY)/$(PREFIX)/transcription-collector:$(TAG)"
	@echo "   $(GCP_REGISTRY)/$(PREFIX)/whisperlive:cpu-$(TAG)"
	@echo "   $(GCP_REGISTRY)/$(PREFIX)/whisperlive:gpu-$(TAG)"

push-gcr-admin-api:
	@echo "📦 Pushing admin-api to GCR"
	docker tag $(PREFIX)/admin-api:$(TAG) $(GCP_REGISTRY)/$(PREFIX)/admin-api:$(TAG)
	docker push $(GCP_REGISTRY)/$(PREFIX)/admin-api:$(TAG)

push-gcr-api-gateway:
	@echo "📦 Pushing api-gateway to GCR"
	docker tag $(PREFIX)/api-gateway:$(TAG) $(GCP_REGISTRY)/$(PREFIX)/api-gateway:$(TAG)
	docker push $(GCP_REGISTRY)/$(PREFIX)/api-gateway:$(TAG)

push-gcr-vexa-bot:
	@echo "📦 Pushing vexa-bot to GCR"
	docker tag $(PREFIX)/vexa-bot:$(TAG) $(GCP_REGISTRY)/$(PREFIX)/vexa-bot:$(TAG)
	docker push $(GCP_REGISTRY)/$(PREFIX)/vexa-bot:$(TAG)

push-gcr-bot-manager:
	@echo "📦 Pushing bot-manager to GCR"
	docker tag $(PREFIX)/bot-manager:$(TAG) $(GCP_REGISTRY)/$(PREFIX)/bot-manager:$(TAG)
	docker push $(GCP_REGISTRY)/$(PREFIX)/bot-manager:$(TAG)

push-gcr-transcription-collector:
	@echo "📦 Pushing transcription-collector to GCR"
	docker tag $(PREFIX)/transcription-collector:$(TAG) $(GCP_REGISTRY)/$(PREFIX)/transcription-collector:$(TAG)
	docker push $(GCP_REGISTRY)/$(PREFIX)/transcription-collector:$(TAG)

push-gcr-whisperlive-cpu:
	@echo "📦 Pushing WhisperLive CPU to GCR"
	docker tag $(PREFIX)/whisperlive:cpu-$(TAG) $(GCP_REGISTRY)/$(PREFIX)/whisperlive:cpu-$(TAG)
	docker push $(GCP_REGISTRY)/$(PREFIX)/whisperlive:cpu-$(TAG)

push-gcr-whisperlive-gpu:
	@echo "📦 Pushing WhisperLive GPU to GCR"
	docker tag $(PREFIX)/whisperlive:gpu-$(TAG) $(GCP_REGISTRY)/$(PREFIX)/whisperlive:gpu-$(TAG)
	docker push $(GCP_REGISTRY)/$(PREFIX)/whisperlive:gpu-$(TAG)

# Show GCR registry contents
gcr-ls:
	@echo "Images in GCP Container Registry for project $(GCP_PROJECT):"
	@gcloud container images list --repository=$(GCP_REGISTRY) --format="table(name)" 2>/dev/null || echo "No images found or registry not accessible"

# Show detailed image tags for a specific service
gcr-tags:
	@echo "Usage: make gcr-tags SERVICE=admin-api"
	@if [ "$(SERVICE)" ]; then \
		echo "Tags for $(GCP_REGISTRY)/$(PREFIX)/$(SERVICE):"; \
		gcloud container images list-tags $(GCP_REGISTRY)/$(PREFIX)/$(SERVICE) --format="table(digest,tags,timestamp)" || echo "Service $(SERVICE) not found"; \
	else \
		echo "Please specify SERVICE (e.g., admin-api, vexa-bot, bot-manager)"; \
	fi

# Clean GCR images (be careful!)
clean-gcr:
	@echo "⚠️  WARNING: This will delete ALL images in GCR for this project!"
	@echo "Project: $(GCP_PROJECT)"
	@echo "Registry: $(GCP_REGISTRY)"
	@read -p "Are you sure? Type 'yes' to continue: " confirm && [ "$$confirm" = "yes" ] || exit 1
	@gcloud container images list --repository=$(GCP_REGISTRY) --format="value(name)" | xargs -I {} gcloud container images delete {} --force-delete-tags --quiet

# All-in-one: Build, Push to GCR, and Update Nomad Jobs
deploy-gcr: push-gcr
	@echo "🔄 Updating Nomad job files to use GCR images..."
	@./scripts/update-to-gcr.sh
	@echo ""
	@echo "🎉 Complete GCR deployment ready!"
	@echo "📋 All images built, pushed to GCR, and Nomad jobs updated"
	@echo ""
	@echo "🚀 Next steps to deploy:"
	@echo "   sudo systemctl restart nomad"
	@echo "   nomad job run jobs/redis.nomad.hcl"
	@echo "   nomad job run jobs/bot-manager.nomad.hcl"
	@echo "   nomad job run jobs/whisperlive-cpu.nomad.hcl"
	@echo "   nomad job run jobs/admin-api.nomad.hcl"
	@echo "   nomad job run jobs/api-gateway.nomad.hcl"
	@echo "   nomad job run jobs/transcription-collector.nomad.hcl"

# Register the parameterized vexa-bot job (required for bot dispatch)
register-vexa-bot:
	@echo "🤖 Registering parameterized vexa-bot job with Nomad..."
	nomad job run jobs/vexa-bot.nomad.hcl
	@echo "✅ vexa-bot job registered successfully"

# Deploy core services with proper dependency order
deploy-core-services: register-vexa-bot
	@echo "🚀 Deploying core services in dependency order..."
	@echo "   1. Redis (database)"
	nomad job run jobs/redis.nomad.hcl
	@echo "   2. Admin API (user management)"
	nomad job run jobs/admin-api.nomad.hcl
	@echo "   3. Bot Manager (orchestration)"
	nomad job run jobs/bot-manager.nomad.hcl
	@echo "   4. Transcription Collector (data processing)"
	nomad job run jobs/transcription-collector.nomad.hcl
	@echo "   5. WhisperLive CPU (speech processing)"
	nomad job run jobs/whisperlive-cpu.nomad.hcl
	@echo "   6. API Gateway (frontend)"
	nomad job run jobs/api-gateway.nomad.hcl
	@echo "✅ All core services deployed successfully!"

# Docker Hub Management
# Push all images to Docker Hub
push-dockerhub: build-all
	@echo "Pushing all images to Docker Hub: $(DOCKERHUB_USER)"
	@docker login
	@$(MAKE) push-dockerhub-admin-api
	@$(MAKE) push-dockerhub-api-gateway
	@$(MAKE) push-dockerhub-vexa-bot
	@$(MAKE) push-dockerhub-bot-manager
	@$(MAKE) push-dockerhub-transcription-collector
	@$(MAKE) push-dockerhub-whisperlive-cpu
	@$(MAKE) push-dockerhub-whisperlive-gpu
	@echo "✅ All images pushed to Docker Hub successfully!"
	@echo ""
	@echo "📋 To use Docker Hub images in Nomad jobs, update image references:"
	@echo "   $(DOCKERHUB_USER)/admin-api:$(TAG)"
	@echo "   $(DOCKERHUB_USER)/api-gateway:$(TAG)"
	@echo "   $(DOCKERHUB_USER)/vexa-bot:$(TAG)"
	@echo "   $(DOCKERHUB_USER)/bot-manager:$(TAG)"
	@echo "   $(DOCKERHUB_USER)/transcription-collector:$(TAG)"
	@echo "   $(DOCKERHUB_USER)/whisperlive:cpu-$(TAG)"
	@echo "   $(DOCKERHUB_USER)/whisperlive:gpu-$(TAG)"

push-dockerhub-admin-api:
	@echo "📦 Pushing admin-api to Docker Hub"
	docker tag $(PREFIX)/admin-api:$(TAG) $(DOCKERHUB_USER)/admin-api:$(TAG)
	docker push $(DOCKERHUB_USER)/admin-api:$(TAG)

push-dockerhub-api-gateway:
	@echo "📦 Pushing api-gateway to Docker Hub"
	docker tag $(PREFIX)/api-gateway:$(TAG) $(DOCKERHUB_USER)/api-gateway:$(TAG)
	docker push $(DOCKERHUB_USER)/api-gateway:$(TAG)

push-dockerhub-vexa-bot:
	@echo "📦 Pushing vexa-bot to Docker Hub"
	docker tag $(PREFIX)/vexa-bot:$(TAG) $(DOCKERHUB_USER)/vexa-bot:$(TAG)
	docker push $(DOCKERHUB_USER)/vexa-bot:$(TAG)

push-dockerhub-bot-manager:
	@echo "📦 Pushing bot-manager to Docker Hub"
	docker tag $(PREFIX)/bot-manager:$(TAG) $(DOCKERHUB_USER)/bot-manager:$(TAG)
	docker push $(DOCKERHUB_USER)/bot-manager:$(TAG)

push-dockerhub-transcription-collector:
	@echo "📦 Pushing transcription-collector to Docker Hub"
	docker tag $(PREFIX)/transcription-collector:$(TAG) $(DOCKERHUB_USER)/transcription-collector:$(TAG)
	docker push $(DOCKERHUB_USER)/transcription-collector:$(TAG)

push-dockerhub-whisperlive-cpu:
	@echo "📦 Pushing WhisperLive CPU to Docker Hub"
	docker tag $(PREFIX)/whisperlive:cpu-$(TAG) $(DOCKERHUB_USER)/whisperlive:cpu-$(TAG)
	docker push $(DOCKERHUB_USER)/whisperlive:cpu-$(TAG)

push-dockerhub-whisperlive-gpu:
	@echo "📦 Pushing WhisperLive GPU to Docker Hub"
	docker tag $(PREFIX)/whisperlive:gpu-$(TAG) $(DOCKERHUB_USER)/whisperlive:gpu-$(TAG)
	docker push $(DOCKERHUB_USER)/whisperlive:gpu-$(TAG)

# All-in-one: Build, Push to Docker Hub, and Update Nomad Jobs
deploy-dockerhub: push-dockerhub
	@echo "🔄 Updating Nomad job files to use Docker Hub images..."
	@./scripts/update-to-dockerhub.sh
	@$(MAKE) deploy-core-services
	@echo ""
	@echo "🎉 Complete Docker Hub deployment finished!"
	@echo "📋 All images built, pushed to Docker Hub, and services deployed"

# Help target
help:
	@echo "Available targets:"
	@echo "  build          - Build all images locally with :dev tags"
	@echo "  push-gcr       - Build and push all images to Google Container Registry"
	@echo "  deploy-gcr     - Build, push to GCR, and update Nomad job files"
	@echo "  push-dockerhub - Build and push all images to Docker Hub"
	@echo "  deploy-dockerhub - Build, push, and deploy all services to Docker Hub"
	@echo "  register-vexa-bot - Register parameterized vexa-bot job with Nomad"
	@echo "  deploy-core-services - Deploy all core services in proper order"
	@echo "  gcr-ls         - List images in GCR"
	@echo "  gcr-tags       - Show tags for specific service (use SERVICE=name)"
	@echo "  show-images    - Show locally built images"
	@echo "  clean          - Remove local images"
	@echo "  clean-gcr      - Remove all GCR images (dangerous!)" 