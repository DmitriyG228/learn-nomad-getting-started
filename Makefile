# Root Makefile to build local :dev images for Nomad development

TAG ?= dev
PREFIX ?= services

.PHONY: build build-vexa-bot build-bot-manager build-json-debug clean

# Default target builds all images
build: build-vexa-bot build-bot-manager build-json-debug
	@echo "All images built with tag $(TAG)"

build-vexa-bot:
	@echo "Building vexa-bot from vexa/services/vexa-bot/core"
	docker build -t $(PREFIX)/vexa-bot:$(TAG) vexa/services/vexa-bot/core

build-bot-manager:
	@echo "Building bot-manager from vexa/services/bot-manager"
	docker build -t $(PREFIX)/bot-manager:$(TAG) -f vexa/services/bot-manager/Dockerfile vexa

build-json-debug:
	@echo "Building json-debug harness"
	docker build -t $(PREFIX)/json-debug:$(TAG) debug-json

clean:
	docker image ls $(PREFIX)/*:$(TAG) --format '{{.Repository}}:{{.Tag}}' | xargs -r docker rmi -f 