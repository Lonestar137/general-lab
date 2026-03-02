#!/usr/bin/env bash
#
# ITAR-Compliant Self-Signed Certificate Generator for Ollama SSL Proxy
# Generates RSA 4096-bit certificates with proper SAN support
#
# Usage: ./generate-certs.sh [OPTIONS]
#   -d, --domain      Primary domain name (default: localhost)
#   -a, --altnames    Comma-separated list of alternative names
#   -o, --output      Output directory for certificates (default: ./certs)
#   -v, --validity    Certificate validity in days (default: 365)
#   -h, --help        Show this help message
#
# Example:
#   ./generate-certs.sh -d ollama.local -a "ollama.internal,192.168.1.100" -v 730
#

set -euo pipefail

# Default configuration
DOMAIN="localhost"
ALT_NAMES=""
OUTPUT_DIR="./certs"
VALIDITY_DAYS=365
KEY_SIZE=4096
DIGEST="sha384"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

show_help() {
    head -20 "$0" | tail -15
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -a|--altnames)
            ALT_NAMES="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -v|--validity)
            VALIDITY_DAYS="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            ;;
    esac
done

# Validate dependencies
if ! command -v openssl &> /dev/null; then
    log_error "OpenSSL is required but not installed."
    exit 1
fi

# Create output directory with secure permissions
mkdir -p "${OUTPUT_DIR}"
chmod 700 "${OUTPUT_DIR}"

log_info "Generating ITAR-compliant certificates..."
log_info "Domain: ${DOMAIN}"
log_info "Key Size: ${KEY_SIZE}-bit RSA"
log_info "Digest: ${DIGEST}"
log_info "Validity: ${VALIDITY_DAYS} days"

# Build Subject Alternative Names
SAN_CONFIG="[SAN]\nsubjectAltName=DNS:${DOMAIN},DNS:localhost,IP:127.0.0.1"

# Add additional alt names if provided
if [[ -n "${ALT_NAMES}" ]]; then
    IFS=',' read -ra NAMES <<< "${ALT_NAMES}"
    for name in "${NAMES[@]}"; do
        name=$(echo "$name" | xargs) # trim whitespace
        if [[ $name =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            # It's an IP address
            SAN_CONFIG="${SAN_CONFIG},IP:${name}"
            log_info "Adding IP SAN: ${name}"
        else
            # It's a DNS name
            SAN_CONFIG="${SAN_CONFIG},DNS:${name}"
            log_info "Adding DNS SAN: ${name}"
        fi
    done
fi

# Create OpenSSL configuration file
OPENSSL_CONFIG=$(mktemp)
trap "rm -f ${OPENSSL_CONFIG}" EXIT

cat > "${OPENSSL_CONFIG}" << EOF
[req]
default_bits = ${KEY_SIZE}
default_md = ${DIGEST}
distinguished_name = req_distinguished_name
req_extensions = v3_req
x509_extensions = v3_ca
prompt = no

[req_distinguished_name]
C = US
ST = Secure
L = Secure Location
O = ITAR Secure Ollama
OU = AI Infrastructure
CN = ${DOMAIN}

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[v3_ca]
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN}
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF

# Add additional alt names to config
alt_dns_count=3
alt_ip_count=2
if [[ -n "${ALT_NAMES}" ]]; then
    IFS=',' read -ra NAMES <<< "${ALT_NAMES}"
    for name in "${NAMES[@]}"; do
        name=$(echo "$name" | xargs)
        if [[ $name =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "IP.${alt_ip_count} = ${name}" >> "${OPENSSL_CONFIG}"
            ((alt_ip_count++))
        else
            echo "DNS.${alt_dns_count} = ${name}" >> "${OPENSSL_CONFIG}"
            ((alt_dns_count++))
        fi
    done
fi

# Generate CA private key (ITAR: 4096-bit RSA minimum)
log_info "Generating CA private key (${KEY_SIZE}-bit RSA)..."
openssl genrsa -out "${OUTPUT_DIR}/ca.key" ${KEY_SIZE} 2>/dev/null
chmod 600 "${OUTPUT_DIR}/ca.key"

# Generate CA certificate
log_info "Generating CA certificate..."
openssl req -new -x509 \
    -days ${VALIDITY_DAYS} \
    -key "${OUTPUT_DIR}/ca.key" \
    -out "${OUTPUT_DIR}/ca.crt" \
    -config "${OPENSSL_CONFIG}" \
    -extensions v3_ca

# Generate server private key
log_info "Generating server private key..."
openssl genrsa -out "${OUTPUT_DIR}/server.key" ${KEY_SIZE} 2>/dev/null
chmod 600 "${OUTPUT_DIR}/server.key"

# Generate Certificate Signing Request
log_info "Generating CSR..."
openssl req -new \
    -key "${OUTPUT_DIR}/server.key" \
    -out "${OUTPUT_DIR}/server.csr" \
    -config "${OPENSSL_CONFIG}"

# Sign the server certificate with our CA
log_info "Signing server certificate..."
openssl x509 -req \
    -days ${VALIDITY_DAYS} \
    -in "${OUTPUT_DIR}/server.csr" \
    -CA "${OUTPUT_DIR}/ca.crt" \
    -CAkey "${OUTPUT_DIR}/ca.key" \
    -CAcreateserial \
    -out "${OUTPUT_DIR}/server.crt" \
    -extfile "${OPENSSL_CONFIG}" \
    -extensions v3_req 2>/dev/null

# Create combined certificate chain
cat "${OUTPUT_DIR}/server.crt" "${OUTPUT_DIR}/ca.crt" > "${OUTPUT_DIR}/server-chain.crt"

# Generate DH parameters for perfect forward secrecy (ITAR requirement)
log_info "Generating DH parameters (4096-bit, this may take a while)..."
openssl dhparam -out "${OUTPUT_DIR}/dhparam.pem" 4096 2>/dev/null

# Set secure permissions on all files
chmod 600 "${OUTPUT_DIR}"/*.key
chmod 644 "${OUTPUT_DIR}"/*.crt "${OUTPUT_DIR}"/*.pem
chmod 600 "${OUTPUT_DIR}/server.csr"

# Clean up CSR (not needed after signing)
rm -f "${OUTPUT_DIR}/server.csr"

# Verify the certificate
log_info "Verifying certificate chain..."
if openssl verify -CAfile "${OUTPUT_DIR}/ca.crt" "${OUTPUT_DIR}/server.crt" > /dev/null 2>&1; then
    log_info "Certificate verification: PASSED"
else
    log_error "Certificate verification: FAILED"
    exit 1
fi

# Display certificate information
log_info "Certificate Details:"
openssl x509 -in "${OUTPUT_DIR}/server.crt" -noout -text | grep -A1 "Subject:"
openssl x509 -in "${OUTPUT_DIR}/server.crt" -noout -text | grep -A1 "Subject Alternative Name" | tail -1

echo ""
log_info "Certificates generated successfully in ${OUTPUT_DIR}/"
log_info "Files created:"
ls -la "${OUTPUT_DIR}/"

echo ""
log_warn "SECURITY NOTES (ITAR Compliance):"
echo "  1. Keep ca.key and server.key files secure and confidential"
echo "  2. The CA certificate (ca.crt) should be distributed to clients"
echo "  3. Do not commit private keys to version control"
echo "  4. Rotate certificates before expiration (${VALIDITY_DAYS} days)"
echo "  5. Store keys in a secure, access-controlled location"
