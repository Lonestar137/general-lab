#!/bin/sh
#
# ITAR-Compliant Nginx Entrypoint Script
# Handles SSL certificate setup, authentication, and IP whitelist configuration
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

# Validate IP address or CIDR format
validate_ip_or_cidr() {
    local ip="$1"
    # IPv4 with optional CIDR
    if echo "$ip" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$'; then
        return 0
    fi
    # IPv6 with optional CIDR
    if echo "$ip" | grep -qE '^([0-9a-fA-F:]+)(/[0-9]{1,3})?$'; then
        return 0
    fi
    return 1
}

# Verify SSL certificates exist
verify_ssl_certs() {
    local ssl_dir="/etc/nginx/ssl"
    local required_files="server-chain.crt server.key dhparam.pem"
    
    for file in $required_files; do
        if [ ! -f "${ssl_dir}/${file}" ]; then
            log_error "Missing required SSL file: ${ssl_dir}/${file}"
            log_error "Please mount SSL certificates or run the generate-certs.sh script"
            exit 1
        fi
    done
    
    # Verify certificate is valid
    if ! openssl x509 -in "${ssl_dir}/server-chain.crt" -noout -checkend 0 2>/dev/null; then
        log_error "SSL certificate has expired!"
        exit 1
    fi
    
    # Check certificate expiration warning (30 days)
    if ! openssl x509 -in "${ssl_dir}/server-chain.crt" -noout -checkend 2592000 2>/dev/null; then
        log_warn "SSL certificate will expire within 30 days. Please renew."
    fi
    
    log_info "SSL certificates verified successfully"
}

# Configure authentication
configure_auth() {
    local auth_conf="/etc/nginx/conf.d/auth.conf"
    
    if [ "${AUTH_ENABLED}" = "true" ]; then
        log_info "Authentication is ENABLED"
        
        # Check if using API token or basic auth
        if [ -n "${API_TOKEN}" ]; then
            log_info "Configuring API Token authentication"
            cat > "${auth_conf}" << EOF
# API Token Authentication
set \$auth_ok 0;
if (\$http_authorization = "Bearer ${API_TOKEN}") {
    set \$auth_ok 1;
}
if (\$auth_ok = 0) {
    return 401 '{"error": "Unauthorized - Invalid or missing API token"}';
}
EOF
        elif [ -n "${AUTH_PASSWORD}" ]; then
            log_info "Configuring Basic HTTP authentication"
            
            # Create htpasswd file
            htpasswd -bc /etc/nginx/auth/.htpasswd "${AUTH_USER:-admin}" "${AUTH_PASSWORD}"
            chmod 600 /etc/nginx/auth/.htpasswd
            
            cat > "${auth_conf}" << EOF
# Basic HTTP Authentication
auth_basic "Ollama Secure API - Authorization Required";
auth_basic_user_file /etc/nginx/auth/.htpasswd;
EOF
        else
            log_error "AUTH_ENABLED=true but neither AUTH_PASSWORD nor API_TOKEN is set"
            exit 1
        fi
    else
        log_warn "Authentication is DISABLED - API is publicly accessible on the network"
        # Create empty auth config
        echo "# Authentication disabled" > "${auth_conf}"
    fi
}

# Configure IP whitelist
configure_whitelist() {
    local whitelist_conf="/etc/nginx/conf.d/ip-whitelist.conf"
    local whitelist_check="/etc/nginx/conf.d/whitelist-check.conf"
    
    if [ "${WHITELIST_ENABLED}" = "true" ]; then
        log_info "IP Whitelist is ENABLED"
        
        # Start with base whitelist (localhost and container network)
        cat > "${whitelist_conf}" << 'EOF'
# IP Whitelist - Auto-generated
# Only listed IPs/CIDRs can access the server

# Localhost (always allowed)
127.0.0.1       1;
::1             1;

# Container internal network
172.28.0.0/24   1;
EOF

        # Parse WHITELIST_IPS environment variable
        if [ -n "${WHITELIST_IPS}" ]; then
            log_info "Processing whitelist entries..."
            
            # Split by comma and process each entry
            echo "${WHITELIST_IPS}" | tr ',' '\n' | while read -r entry; do
                # Trim whitespace
                entry=$(echo "$entry" | xargs)
                
                if [ -n "$entry" ]; then
                    if validate_ip_or_cidr "$entry"; then
                        log_info "  Whitelisting: $entry"
                        echo "${entry}    1;" >> "${whitelist_conf}"
                    else
                        log_warn "  Invalid IP/CIDR format, skipping: $entry"
                    fi
                fi
            done
        else
            log_warn "WHITELIST_ENABLED=true but WHITELIST_IPS is empty"
            log_warn "Only localhost and container network will be allowed"
        fi
        
        # Create whitelist enforcement config
        cat > "${whitelist_check}" << 'EOF'
# Whitelist Enforcement - Auto-generated
# Denies all traffic from IPs not in the whitelist

if ($whitelist_status = 0) {
    return 403 '{"error": "Forbidden - IP not whitelisted", "client_ip": "$remote_addr"}';
}
EOF
        
        # Count whitelisted entries
        local count=$(grep -c "1;$" "${whitelist_conf}" 2>/dev/null || echo "0")
        log_info "IP Whitelist configured with ${count} entries"
        
    else
        log_info "IP Whitelist is DISABLED - all IPs can access (subject to auth)"
        # Create empty configs so nginx include doesn't fail
        echo "# Whitelist disabled - all IPs allowed" > "${whitelist_conf}"
        echo "# Whitelist check disabled" > "${whitelist_check}"
    fi
}

# Security checks
security_checks() {
    log_info "Running security checks..."
    
    # Check SSL key permissions
    local key_perms=$(stat -c %a /etc/nginx/ssl/server.key 2>/dev/null || echo "000")
    if [ "$key_perms" != "600" ] && [ "$key_perms" != "400" ]; then
        log_warn "SSL private key has loose permissions: ${key_perms}. Fixing..."
        chmod 600 /etc/nginx/ssl/server.key 2>/dev/null || true
    fi
    
    # Verify nginx config syntax
    if ! nginx -t 2>/dev/null; then
        log_error "Nginx configuration test failed"
        nginx -t
        exit 1
    fi
    
    log_info "Security checks passed"
}

# Main
log_info "Starting ITAR-Compliant Nginx SSL Proxy"
log_info "============================================"

verify_ssl_certs
configure_whitelist
configure_auth
security_checks

log_info "Configuration complete. Starting nginx..."
log_info "============================================"

# Execute the main command
exec "$@"
