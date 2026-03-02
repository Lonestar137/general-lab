#!/usr/bin/env bash
#
# ITAR Security Audit Script for Ollama Deployment
# Performs security checks and generates compliance report
#
# Usage: ./security-audit.sh [--verbose] [--fix]
#

set -euo pipefail

VERBOSE=false
AUTO_FIX=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
AUDIT_LOG="${PROJECT_DIR}/data/logs/security-audit-$(date +%Y%m%d-%H%M%S).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose) VERBOSE=true; shift ;;
        -f|--fix) AUTO_FIX=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

log() {
    echo "$1" | tee -a "$AUDIT_LOG"
}

check_pass() {
    echo -e "${GREEN}[PASS]${NC} $1" | tee -a "$AUDIT_LOG"
    ((PASS_COUNT++))
}

check_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$AUDIT_LOG"
    ((WARN_COUNT++))
}

check_fail() {
    echo -e "${RED}[FAIL]${NC} $1" | tee -a "$AUDIT_LOG"
    ((FAIL_COUNT++))
}

check_info() {
    if $VERBOSE; then
        echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$AUDIT_LOG"
    fi
}

# Ensure log directory exists
mkdir -p "$(dirname "$AUDIT_LOG")"

log ""
log "=============================================="
log "ITAR Security Audit for Ollama Deployment"
log "Date: $(date)"
log "=============================================="
log ""

# 1. SSL Certificate Checks
log "--- SSL Certificate Checks ---"

CERT_DIR="${PROJECT_DIR}/certs"

if [ -d "$CERT_DIR" ]; then
    # Check certificate exists
    if [ -f "$CERT_DIR/server.crt" ]; then
        check_pass "Server certificate exists"
        
        # Check key strength
        KEY_SIZE=$(openssl x509 -in "$CERT_DIR/server.crt" -noout -text 2>/dev/null | grep "Public-Key:" | grep -oP '\d+' || echo "0")
        if [ "$KEY_SIZE" -ge 4096 ]; then
            check_pass "Certificate key size is ${KEY_SIZE} bits (>=4096 required for ITAR)"
        elif [ "$KEY_SIZE" -ge 2048 ]; then
            check_warn "Certificate key size is ${KEY_SIZE} bits (4096+ recommended for ITAR)"
        else
            check_fail "Certificate key size is ${KEY_SIZE} bits (minimum 2048 required)"
        fi
        
        # Check certificate expiration
        if openssl x509 -in "$CERT_DIR/server.crt" -noout -checkend 0 2>/dev/null; then
            check_pass "Certificate is not expired"
            
            # Check if expiring soon (30 days)
            if openssl x509 -in "$CERT_DIR/server.crt" -noout -checkend 2592000 2>/dev/null; then
                check_pass "Certificate valid for more than 30 days"
            else
                check_warn "Certificate expires within 30 days - plan renewal"
            fi
        else
            check_fail "Certificate has EXPIRED"
        fi
        
        # Check signature algorithm
        SIG_ALG=$(openssl x509 -in "$CERT_DIR/server.crt" -noout -text 2>/dev/null | grep "Signature Algorithm:" | head -1 | awk '{print $3}')
        if [[ "$SIG_ALG" =~ sha(256|384|512) ]]; then
            check_pass "Certificate uses strong signature algorithm: $SIG_ALG"
        else
            check_warn "Certificate signature algorithm may be weak: $SIG_ALG"
        fi
    else
        check_fail "Server certificate not found"
    fi
    
    # Check private key permissions
    if [ -f "$CERT_DIR/server.key" ]; then
        KEY_PERMS=$(stat -c %a "$CERT_DIR/server.key" 2>/dev/null || echo "000")
        if [ "$KEY_PERMS" = "600" ] || [ "$KEY_PERMS" = "400" ]; then
            check_pass "Private key has secure permissions ($KEY_PERMS)"
        else
            check_fail "Private key has insecure permissions ($KEY_PERMS) - should be 600 or 400"
            if $AUTO_FIX; then
                chmod 600 "$CERT_DIR/server.key"
                check_info "Fixed: Set private key permissions to 600"
            fi
        fi
    fi
    
    # Check DH parameters
    if [ -f "$CERT_DIR/dhparam.pem" ]; then
        DH_SIZE=$(openssl dhparam -in "$CERT_DIR/dhparam.pem" -text 2>/dev/null | grep "DH Parameters:" | grep -oP '\d+' || echo "0")
        if [ "$DH_SIZE" -ge 4096 ]; then
            check_pass "DH parameters are ${DH_SIZE} bits (Strong)"
        elif [ "$DH_SIZE" -ge 2048 ]; then
            check_warn "DH parameters are ${DH_SIZE} bits (4096 recommended for ITAR)"
        else
            check_fail "DH parameters are weak (${DH_SIZE} bits)"
        fi
    else
        check_fail "DH parameters file not found (required for PFS)"
    fi
else
    check_fail "Certificate directory not found: $CERT_DIR"
fi

log ""

# 2. Container Security Checks
log "--- Container Security Checks ---"

# Check if podman is available
if command -v podman &> /dev/null; then
    check_pass "Podman is installed"
    
    # Check for running containers
    if podman ps --format "{{.Names}}" 2>/dev/null | grep -q "ollama"; then
        check_info "Ollama containers are running"
        
        # Check container user
        OLLAMA_USER=$(podman inspect ollama-server --format '{{.Config.User}}' 2>/dev/null || echo "root")
        if [ "$OLLAMA_USER" != "root" ] && [ "$OLLAMA_USER" != "0" ] && [ -n "$OLLAMA_USER" ]; then
            check_pass "Ollama container runs as non-root user: $OLLAMA_USER"
        else
            check_warn "Ollama container may be running as root"
        fi
        
        # Check network isolation
        OLLAMA_NETWORKS=$(podman inspect ollama-server --format '{{range .NetworkSettings.Networks}}{{.NetworkID}} {{end}}' 2>/dev/null || echo "")
        if [ -n "$OLLAMA_NETWORKS" ]; then
            check_pass "Ollama container has network configuration"
        fi
    else
        check_info "Ollama containers are not currently running"
    fi
else
    check_warn "Podman not installed - cannot check container security"
fi

log ""

# 3. File Permission Checks
log "--- File Permission Checks ---"

# Check .env file
if [ -f "${PROJECT_DIR}/.env" ]; then
    ENV_PERMS=$(stat -c %a "${PROJECT_DIR}/.env" 2>/dev/null || echo "000")
    if [ "$ENV_PERMS" = "600" ] || [ "$ENV_PERMS" = "400" ]; then
        check_pass ".env file has secure permissions ($ENV_PERMS)"
    else
        check_warn ".env file has loose permissions ($ENV_PERMS) - should be 600"
        if $AUTO_FIX; then
            chmod 600 "${PROJECT_DIR}/.env"
            check_info "Fixed: Set .env permissions to 600"
        fi
    fi
    
    # Check for sensitive data in .env
    if grep -qE "^(AUTH_PASSWORD|API_TOKEN)=.+" "${PROJECT_DIR}/.env" 2>/dev/null; then
        check_pass "Authentication credentials are configured"
    else
        check_warn "No authentication credentials found in .env"
    fi
else
    check_info ".env file not found (using defaults)"
fi

# Check data directories
for dir in "data/models" "data/logs"; do
    if [ -d "${PROJECT_DIR}/${dir}" ]; then
        DIR_PERMS=$(stat -c %a "${PROJECT_DIR}/${dir}" 2>/dev/null || echo "000")
        if [ "$DIR_PERMS" = "700" ] || [ "$DIR_PERMS" = "750" ]; then
            check_pass "${dir} directory has secure permissions ($DIR_PERMS)"
        else
            check_warn "${dir} directory has loose permissions ($DIR_PERMS)"
            if $AUTO_FIX; then
                chmod 700 "${PROJECT_DIR}/${dir}"
                check_info "Fixed: Set ${dir} permissions to 700"
            fi
        fi
    fi
done

log ""

# 4. Configuration Checks
log "--- Configuration Checks ---"

# Check nginx.conf for security headers
if [ -f "${PROJECT_DIR}/nginx/nginx.conf" ]; then
    if grep -q "Strict-Transport-Security" "${PROJECT_DIR}/nginx/nginx.conf"; then
        check_pass "HSTS header is configured"
    else
        check_fail "HSTS header is missing"
    fi
    
    if grep -q "TLSv1.3" "${PROJECT_DIR}/nginx/nginx.conf"; then
        check_pass "TLS 1.3 is configured"
    else
        check_warn "TLS 1.3 may not be configured"
    fi
    
    if grep -q "ssl_prefer_server_ciphers" "${PROJECT_DIR}/nginx/nginx.conf"; then
        check_pass "Server cipher preference is configured"
    fi
    
    if grep -q "X-Content-Type-Options" "${PROJECT_DIR}/nginx/nginx.conf"; then
        check_pass "X-Content-Type-Options header configured"
    fi
    
    if grep -q "X-Frame-Options" "${PROJECT_DIR}/nginx/nginx.conf"; then
        check_pass "X-Frame-Options header configured"
    fi
fi

log ""

# 5. Network Security Checks
log "--- Network Security Checks ---"

# Check if internal network is properly isolated
if [ -f "${PROJECT_DIR}/podman-compose.yml" ]; then
    if grep -q "internal: true" "${PROJECT_DIR}/podman-compose.yml"; then
        check_pass "Internal network isolation is configured"
    else
        check_warn "Internal network isolation may not be configured"
    fi
    
    if grep -q "no-new-privileges" "${PROJECT_DIR}/podman-compose.yml"; then
        check_pass "no-new-privileges security option is set"
    fi
    
    if grep -q "cap_drop" "${PROJECT_DIR}/podman-compose.yml"; then
        check_pass "Capabilities are dropped"
    fi
fi

log ""

# 6. IP Whitelist Checks
log "--- IP Whitelist Security Checks ---"

# Check .env for whitelist configuration
if [ -f "${PROJECT_DIR}/.env" ]; then
    WHITELIST_ENABLED=$(grep -E "^WHITELIST_ENABLED=" "${PROJECT_DIR}/.env" 2>/dev/null | cut -d= -f2 || echo "false")
    WHITELIST_IPS=$(grep -E "^WHITELIST_IPS=" "${PROJECT_DIR}/.env" 2>/dev/null | cut -d= -f2 || echo "")
    
    if [ "$WHITELIST_ENABLED" = "true" ]; then
        check_pass "IP Whitelist is ENABLED (defense in depth)"
        
        if [ -n "$WHITELIST_IPS" ]; then
            # Count whitelist entries
            WHITELIST_COUNT=$(echo "$WHITELIST_IPS" | tr ',' '\n' | grep -c . || echo "0")
            check_pass "IP Whitelist has ${WHITELIST_COUNT} configured entries"
            
            # Check for overly permissive entries
            if echo "$WHITELIST_IPS" | grep -qE "0\.0\.0\.0/0|::/0"; then
                check_fail "Whitelist contains 0.0.0.0/0 or ::/0 - this allows ALL traffic!"
            fi
            
            # Warn about large CIDR ranges
            if echo "$WHITELIST_IPS" | grep -qE "/[0-7]($|,)"; then
                check_warn "Whitelist contains very large CIDR ranges (>/8) - consider narrowing"
            fi
        else
            check_warn "Whitelist enabled but WHITELIST_IPS is empty (only localhost allowed)"
        fi
    else
        check_warn "IP Whitelist is DISABLED - recommend enabling for ITAR compliance"
        check_info "Set WHITELIST_ENABLED=true and configure WHITELIST_IPS in .env"
    fi
else
    check_info "No .env file - whitelist status unknown (default: disabled)"
fi

# Check nginx whitelist config if containers are running
if command -v podman &> /dev/null; then
    if podman ps --format "{{.Names}}" 2>/dev/null | grep -q "ollama-proxy"; then
        # Check if whitelist config exists in running container
        WHITELIST_ACTIVE=$(podman exec ollama-proxy cat /etc/nginx/conf.d/whitelist-check.conf 2>/dev/null | grep -c "whitelist_status" || echo "0")
        if [ "$WHITELIST_ACTIVE" -gt 0 ]; then
            check_pass "Whitelist enforcement is active in running container"
            
            # Count active whitelist entries
            ACTIVE_ENTRIES=$(podman exec ollama-proxy grep -c "1;$" /etc/nginx/conf.d/ip-whitelist.conf 2>/dev/null || echo "0")
            check_info "Active whitelist entries in container: ${ACTIVE_ENTRIES}"
        else
            check_info "Whitelist enforcement not active in running container"
        fi
    fi
fi

log ""

# Summary
log "=============================================="
log "Security Audit Summary"
log "=============================================="
log ""
echo -e "${GREEN}Passed: ${PASS_COUNT}${NC}" | tee -a "$AUDIT_LOG"
echo -e "${YELLOW}Warnings: ${WARN_COUNT}${NC}" | tee -a "$AUDIT_LOG"
echo -e "${RED}Failed: ${FAIL_COUNT}${NC}" | tee -a "$AUDIT_LOG"
log ""

if [ $FAIL_COUNT -gt 0 ]; then
    log "ITAR COMPLIANCE: NOT READY - Address failed checks"
    exit 1
elif [ $WARN_COUNT -gt 0 ]; then
    log "ITAR COMPLIANCE: REVIEW NEEDED - Address warnings for full compliance"
    exit 0
else
    log "ITAR COMPLIANCE: READY - All security checks passed"
    exit 0
fi
