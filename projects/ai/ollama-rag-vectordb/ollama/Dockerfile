# ITAR-Compliant Ollama Server with GPU Support
# Security-hardened container optimized for NVIDIA GPU passthrough

FROM docker.io/ollama/ollama:latest

LABEL maintainer="AI Infrastructure Team"
LABEL description="ITAR-compliant Ollama LLM server with GPU support"
LABEL security.compliance="ITAR"

# Install additional security tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create non-root user for Ollama
RUN groupadd -g 1000 ollama && \
    useradd -u 1000 -g ollama -m -s /bin/bash ollama

# Create directories with proper permissions
RUN mkdir -p /home/ollama/.ollama \
             /var/log/ollama \
    && chown -R ollama:ollama /home/ollama/.ollama \
    && chown -R ollama:ollama /var/log/ollama \
    && chmod 700 /home/ollama/.ollama

# Copy security configuration
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Security hardening
# Remove unnecessary setuid/setgid binaries
RUN find / -perm /6000 -type f -exec chmod a-s {} \; 2>/dev/null || true

# Set Ollama environment variables
ENV OLLAMA_HOST=0.0.0.0:11434
ENV OLLAMA_MODELS=/home/ollama/.ollama/models
ENV OLLAMA_KEEP_ALIVE=24h
ENV OLLAMA_NUM_PARALLEL=4
ENV OLLAMA_MAX_LOADED_MODELS=2

# GPU-specific environment variables
# These can be overridden at runtime
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

# CUDA memory settings for optimization
ENV CUDA_VISIBLE_DEVICES=all

# Ollama security settings
# Disable external origins by default (security)
ENV OLLAMA_ORIGINS=""

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:11434/api/tags || exit 1

# Expose internal port (only accessible via internal network)
EXPOSE 11434

# Volume for model storage
VOLUME ["/home/ollama/.ollama"]

# Switch to non-root user
USER ollama
WORKDIR /home/ollama

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["serve"]
