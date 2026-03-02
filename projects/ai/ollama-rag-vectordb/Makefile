# ITAR-Compliant Ollama Server - Makefile
# Simplifies common operations

.PHONY: help certs build up down logs audit clean pull models

# Default target
help:
	@echo "ITAR-Compliant Ollama Server Commands"
	@echo "======================================"
	@echo ""
	@echo "Setup:"
	@echo "  make certs          Generate SSL certificates"
	@echo "  make certs-custom   Generate certs with custom domain (DOMAIN=xxx ALT_NAMES=xxx)"
	@echo "  make setup          Full setup (dirs, certs, env, build)"
	@echo ""
	@echo "Container Operations:"
	@echo "  make build          Build container images"
	@echo "  make up             Start services"
	@echo "  make down           Stop services"
	@echo "  make restart        Restart services"
	@echo "  make logs           View service logs"
	@echo ""
	@echo "Ollama Operations:"
	@echo "  make pull MODEL=xx  Pull an Ollama model"
	@echo "  make models         List loaded models"
	@echo "  make shell          Open shell in Ollama container"
	@echo ""
	@echo "Security:"
	@echo "  make audit          Run security audit"
	@echo "  make audit-fix      Run security audit and auto-fix issues"
	@echo ""
	@echo "Maintenance:"
	@echo "  make clean          Remove containers and images"
	@echo "  make clean-all      Remove everything including data"

# Variables
DOMAIN ?= localhost
ALT_NAMES ?= 
VALIDITY ?= 365
MODEL ?= llama2

# Setup targets
certs:
	@echo "Generating SSL certificates..."
	./scripts/generate-certs.sh -d $(DOMAIN) -o ./certs -v $(VALIDITY)

certs-custom:
	@echo "Generating SSL certificates with custom SANs..."
	./scripts/generate-certs.sh -d $(DOMAIN) -a "$(ALT_NAMES)" -o ./certs -v $(VALIDITY)

dirs:
	@echo "Creating data directories..."
	mkdir -p data/models data/logs/nginx
	chmod 700 data/models data/logs

env:
	@if [ ! -f .env ]; then \
		echo "Creating .env from template..."; \
		cp .env.example .env; \
		chmod 600 .env; \
		echo "Please edit .env with your configuration"; \
	else \
		echo ".env already exists"; \
	fi

setup: dirs certs env build
	@echo ""
	@echo "Setup complete! Next steps:"
	@echo "1. Edit .env with your configuration"
	@echo "2. Run 'make audit' to verify security"
	@echo "3. Run 'make up' to start services"

# Container targets
build:
	@echo "Building nginx proxy image (Ollama uses official image)..."
	podman-compose build nginx-proxy

up:
	@echo "Starting services..."
	podman-compose up -d
	@echo ""
	@echo "Services started. Access at:"
	@echo "  HTTPS: https://localhost:$${PROXY_HTTPS_PORT:-8443}"

down:
	@echo "Stopping services..."
	podman-compose down

restart: down up

logs:
	podman-compose logs -f

# Ollama targets
pull:
	@echo "Pulling model: $(MODEL)"
	podman exec -it ollama-server ollama pull $(MODEL)

models:
	@echo "Loaded models:"
	podman exec ollama-server ollama list

shell:
	podman exec -it ollama-server /bin/bash

# Security targets
audit:
	@echo "Running security audit..."
	./scripts/security-audit.sh --verbose

audit-fix:
	@echo "Running security audit with auto-fix..."
	./scripts/security-audit.sh --verbose --fix

# Cleanup targets
clean:
	@echo "Removing containers and images..."
	podman-compose down --rmi local -v
	podman image prune -f

clean-all: clean
	@echo "WARNING: This will remove all data including models!"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ]
	rm -rf data/ certs/
	@echo "Cleanup complete"

# Test targets
test-health:
	@echo "Testing health endpoint..."
	curl -sk https://localhost:$${PROXY_HTTPS_PORT:-8443}/health && echo ""

test-api:
	@echo "Testing API (requires AUTH_PASSWORD in env)..."
	@if [ -n "$$AUTH_PASSWORD" ]; then \
		curl -sk -u admin:$$AUTH_PASSWORD https://localhost:$${PROXY_HTTPS_PORT:-8443}/api/tags; \
	else \
		curl -sk https://localhost:$${PROXY_HTTPS_PORT:-8443}/api/tags; \
	fi
	@echo ""
