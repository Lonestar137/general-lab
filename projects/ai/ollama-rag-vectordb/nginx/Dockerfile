# ITAR-Compliant Nginx SSL Proxy for Ollama
# Security-hardened container with TLS 1.3 support

FROM docker.io/library/nginx:1.25-alpine

LABEL maintainer="AI Infrastructure Team"
LABEL description="ITAR-compliant Nginx SSL proxy for Ollama"
LABEL security.compliance="ITAR"

# Install required packages
RUN apk add --no-cache \
    apache2-utils \
    openssl \
    nginx-mod-http-headers-more \
    tzdata \
    && rm -rf /var/cache/apk/*

# Create non-root user for nginx
RUN addgroup -g 1001 -S nginxgroup && \
    adduser -u 1001 -S nginxuser -G nginxgroup

# Create required directories with proper permissions
RUN mkdir -p /etc/nginx/ssl \
             /etc/nginx/auth \
             /etc/nginx/conf.d \
             /var/log/nginx \
             /var/cache/nginx \
             /run \
    && chown -R nginxuser:nginxgroup /etc/nginx/ssl \
    && chown -R nginxuser:nginxgroup /etc/nginx/auth \
    && chown -R nginxuser:nginxgroup /var/log/nginx \
    && chown -R nginxuser:nginxgroup /var/cache/nginx \
    && chown -R nginxuser:nginxgroup /run \
    && chmod 700 /etc/nginx/ssl \
    && chmod 700 /etc/nginx/auth

# Copy configuration files
COPY nginx.conf /etc/nginx/nginx.conf
COPY auth.conf.template /etc/nginx/auth.conf.template
COPY ip-whitelist.conf.template /etc/nginx/ip-whitelist.conf.template
COPY whitelist-check.conf.template /etc/nginx/whitelist-check.conf.template

# Copy entrypoint script
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Security hardening
# Remove default configs
RUN rm -f /etc/nginx/conf.d/default.conf

# Set secure permissions on config
RUN chmod 644 /etc/nginx/nginx.conf \
    && chmod 644 /etc/nginx/auth.conf.template \
    && chmod 644 /etc/nginx/ip-whitelist.conf.template \
    && chmod 644 /etc/nginx/whitelist-check.conf.template

# Create empty config files to satisfy include directives
RUN touch /etc/nginx/conf.d/auth.conf \
    && touch /etc/nginx/conf.d/ip-whitelist.conf \
    && touch /etc/nginx/conf.d/whitelist-check.conf

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider --no-check-certificate https://localhost/health || exit 1

# Expose ports
EXPOSE 80 443

# Environment variables
ENV AUTH_ENABLED=false
ENV AUTH_USER=admin
ENV AUTH_PASSWORD=""
ENV API_TOKEN=""
ENV WHITELIST_ENABLED=false
ENV WHITELIST_IPS=""
ENV TZ=UTC

# Run entrypoint
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
