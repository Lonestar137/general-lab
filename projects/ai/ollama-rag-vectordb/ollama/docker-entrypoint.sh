#!/bin/bash
#
# ITAR-Compliant Ollama Entrypoint Script
# Handles GPU detection and security configuration
#

set -e

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

# Detect and configure GPU
configure_gpu() {
    log_info "Detecting GPU hardware..."
    
    # Check for NVIDIA GPU
    if command -v nvidia-smi &> /dev/null; then
        log_info "NVIDIA GPU detected"
        nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>/dev/null || true
        
        # Set CUDA memory allocation strategy
        export PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-max_split_size_mb:512}"
        
        # Optimize for inference
        export CUDA_LAUNCH_BLOCKING="${CUDA_LAUNCH_BLOCKING:-0}"
        
        log_info "NVIDIA GPU configuration complete"
    elif [ -d "/dev/dri" ]; then
        # Check for AMD/Intel GPU
        log_info "Non-NVIDIA GPU detected (AMD/Intel)"
        log_warn "GPU acceleration may be limited"
    else
        log_warn "No GPU detected - running in CPU-only mode"
        log_warn "LLM inference will be significantly slower"
    fi
}

# Security configuration
configure_security() {
    log_info "Applying security configuration..."
    
    # Verify we're not running as root
    if [ "$(id -u)" = "0" ]; then
        log_error "Container should not run as root for ITAR compliance"
        exit 1
    fi
    
    # Set secure umask
    umask 0077
    
    # Verify model directory permissions
    if [ -d "${OLLAMA_MODELS:-/home/ollama/.ollama/models}" ]; then
        # Ensure only owner can access models
        chmod -R 700 "${OLLAMA_MODELS:-/home/ollama/.ollama/models}" 2>/dev/null || true
    fi
    
    log_info "Security configuration complete"
}

# Verify Ollama origins setting
verify_origins() {
    if [ -n "${OLLAMA_ORIGINS}" ]; then
        log_info "OLLAMA_ORIGINS is set to: ${OLLAMA_ORIGINS}"
        log_warn "Ensure only trusted origins are specified for ITAR compliance"
    else
        log_info "OLLAMA_ORIGINS is empty - only same-origin requests allowed"
    fi
}

# Main
log_info "Starting ITAR-Compliant Ollama Server"
log_info "============================================"

configure_gpu
configure_security
verify_origins

log_info "Ollama Configuration:"
log_info "  Host: ${OLLAMA_HOST:-0.0.0.0:11434}"
log_info "  Models: ${OLLAMA_MODELS:-/home/ollama/.ollama/models}"
log_info "  Keep Alive: ${OLLAMA_KEEP_ALIVE:-5m}"
log_info "  Parallel: ${OLLAMA_NUM_PARALLEL:-1}"
log_info "============================================"

# Execute Ollama
exec /bin/ollama "$@"
