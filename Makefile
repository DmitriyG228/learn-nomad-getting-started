# Root Makefile to build local :dev images for Nomad development

TAG ?= dev
PREFIX ?= services
LOCAL_REGISTRY ?= localhost:5000

.PHONY: build build-all build-admin-api build-api-gateway build-vexa-bot build-bot-manager build-whisperlive-gpu build-whisperlive-cpu build-transcription-collector build-json-debug clean start-registry stop-registry push-local clean-registry registry-ls

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