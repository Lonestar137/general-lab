# ITAR-Compliant Ollama Server - Makefile
# Simplifies common operations

.PHONY: help certs build up up-nvidia up-nvidia-direct up-amd down logs audit clean pull models

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
	@echo "  make build          Build nginx proxy image"
	@echo "  make up             Start services (CPU only)"
	@echo "  make up-nvidia      Start with NVIDIA GPU (requires nvidia-container-toolkit)"
	@echo "  make up-nvidia-direct  Start with NVIDIA GPU (direct device passthrough)"
	@echo "  make up-amd         Start with AMD GPU (ROCm)"
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
	@echo ""
	@echo "GPU Detection:"
	@echo "  make detect-gpu     Detect available GPU hardware"

# Variables
DOMAIN ?= localhost
ALT_NAMES ?= 
VALIDITY ?= 365
MODEL ?= llama3.2

# Compose command
COMPOSE := podman-compose

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
	@echo "2. Run 'make detect-gpu' to check GPU availability"
	@echo "3. Run 'make audit' to verify security"
	@echo "4. Run 'make up', 'make up-nvidia', or 'make up-amd' to start services"

# Container targets
build:
	@echo "Building nginx proxy image (Ollama uses official image)..."
	$(COMPOSE) build nginx-proxy

# CPU only
up:
	@echo "Starting services (CPU only)..."
	$(COMPOSE) up -d
	@echo ""
	@echo "Services started (CPU mode). Access at:"
	@echo "  HTTPS: https://localhost:$${PROXY_HTTPS_PORT:-8443}"

# NVIDIA GPU with container toolkit (CDI)
up-nvidia:
	@echo "Starting services with NVIDIA GPU (container toolkit)..."
	$(COMPOSE) -f podman-compose.yml -f compose.nvidia.yml up -d
	@echo ""
	@echo "Services started (NVIDIA GPU). Access at:"
	@echo "  HTTPS: https://localhost:$${PROXY_HTTPS_PORT:-8443}"

# NVIDIA GPU direct passthrough (no toolkit)
up-nvidia-direct:
	@echo "Starting services with NVIDIA GPU (direct passthrough)..."
	$(COMPOSE) -f podman-compose.yml -f compose.nvidia-direct.yml up -d
	@echo ""
	@echo "Services started (NVIDIA GPU direct). Access at:"
	@echo "  HTTPS: https://localhost:$${PROXY_HTTPS_PORT:-8443}"

# AMD GPU with ROCm
up-amd:
	@echo "Starting services with AMD GPU (ROCm)..."
	$(COMPOSE) -f podman-compose.yml -f compose.amd.yml up -d
	@echo ""
	@echo "Services started (AMD ROCm). Access at:"
	@echo "  HTTPS: https://localhost:$${PROXY_HTTPS_PORT:-8443}"

down:
	@echo "Stopping services..."
	$(COMPOSE) down

restart: down up

restart-nvidia: down up-nvidia

restart-amd: down up-amd

logs:
	$(COMPOSE) logs -f

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
	$(COMPOSE) down --rmi local -v 2>/dev/null || true
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

# GPU detection
detect-gpu:
	@echo "Detecting GPU hardware..."
	@echo ""
	@echo "=== NVIDIA GPU ==="
	@if command -v nvidia-smi >/dev/null 2>&1; then \
		nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>/dev/null || echo "nvidia-smi failed"; \
		echo ""; \
		echo "NVIDIA Container Toolkit:"; \
		if [ -f /etc/cdi/nvidia.yaml ]; then \
			echo "  CDI config found: /etc/cdi/nvidia.yaml"; \
			echo "  Recommended: make up-nvidia"; \
		else \
			echo "  CDI config NOT found"; \
			echo "  Option 1: Install nvidia-container-toolkit and run: sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml"; \
			echo "  Option 2: Use direct passthrough: make up-nvidia-direct"; \
		fi; \
	else \
		echo "No NVIDIA GPU detected (nvidia-smi not found)"; \
	fi
	@echo ""
	@echo "=== AMD GPU ==="
	@if command -v rocminfo >/dev/null 2>&1; then \
		echo "ROCm detected:"; \
		rocminfo 2>/dev/null | grep -E "^\s+Name:" | head -5 || echo "rocminfo failed"; \
		echo ""; \
		echo "GFX Version:"; \
		rocminfo 2>/dev/null | grep -i "gfx" | head -1 || true; \
		echo ""; \
		echo "Recommended: make up-amd"; \
	elif [ -d /dev/dri ] && [ -e /dev/kfd ]; then \
		echo "AMD GPU devices found (/dev/dri, /dev/kfd)"; \
		echo "ROCm not installed - install ROCm for GPU support"; \
		echo "See: https://rocm.docs.amd.com/"; \
	else \
		echo "No AMD GPU detected"; \
	fi
	@echo ""
	@echo "=== Recommendation ==="
	@if command -v nvidia-smi >/dev/null 2>&1; then \
		if [ -f /etc/cdi/nvidia.yaml ]; then \
			echo "Use: make up-nvidia"; \
		else \
			echo "Use: make up-nvidia-direct (or install nvidia-container-toolkit for better support)"; \
		fi; \
	elif command -v rocminfo >/dev/null 2>&1; then \
		echo "Use: make up-amd"; \
	else \
		echo "Use: make up (CPU only)"; \
	fi
