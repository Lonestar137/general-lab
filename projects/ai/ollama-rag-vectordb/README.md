# ITAR-Compliant Ollama Server with SSL Proxy

A secure, containerized deployment of Ollama LLM server with Nginx SSL proxy, designed to meet ITAR (International Traffic in Arms Regulations) security requirements for handling sensitive AI/ML workloads.

## Security Features

### Encryption
- **TLS 1.3 Only** - Modern encryption standard with perfect forward secrecy
- **4096-bit RSA Keys** - Exceeds minimum ITAR requirements
- **SHA-384 Signatures** - Strong cryptographic hash algorithm
- **Custom DH Parameters** - 4096-bit Diffie-Hellman for PFS

### Network Isolation
- **Internal Podman Network** - Ollama server is not directly accessible
- **Nginx Reverse Proxy** - Only entry point with SSL termination
- **Inter-container Communication Disabled** - Prevents lateral movement

### Authentication Options
- **HTTP Basic Authentication** - Username/password protection
- **API Token Authentication** - Bearer token for programmatic access
- **Rate Limiting** - Protection against brute-force attacks

### IP Whitelist (Network Access Control)
- **IP/CIDR Whitelist** - Only allow connections from approved sources
- **Defense in Depth** - Additional layer beyond authentication
- **Automatic Localhost** - Container network always allowed
- **Flexible Configuration** - Support for single IPs and CIDR ranges

### Container Hardening
- **Non-root Execution** - Containers run as unprivileged users
- **Dropped Capabilities** - Minimal Linux capabilities
- **No New Privileges** - Prevents privilege escalation
- **Read-only Filesystems** - Where applicable

### Audit & Compliance
- **Security Audit Script** - Automated compliance checking
- **Comprehensive Logging** - Security-focused log format
- **Certificate Monitoring** - Expiration warnings

## Quick Start

### 1. Generate SSL Certificates

```bash
# Basic generation for localhost
./scripts/generate-certs.sh

# With custom domain and SANs
./scripts/generate-certs.sh \
  -d ollama.yourdomain.com \
  -a "ollama.internal,192.168.1.100" \
  -v 365
```

### 2. Configure Environment

```bash
# Copy example configuration
cp .env.example .env

# Edit with your settings
vim .env
```

Key settings to configure:
- `AUTH_ENABLED=true` - Enable authentication
- `AUTH_PASSWORD=your-secure-password` - Set strong password
- `WHITELIST_ENABLED=true` - Enable IP whitelist (recommended for ITAR)
- `WHITELIST_IPS=192.168.1.0/24,10.0.0.0/8` - Allowed IP ranges
- `SSL_DOMAIN=your-domain.local` - Your server domain

### 3. Create Data Directories

```bash
mkdir -p data/models data/logs/nginx data/logs/ollama
chmod 700 data/models data/logs
```

### 4. Build and Start

```bash
# Build nginx proxy (Ollama uses official image)
podman-compose build nginx-proxy

# Start services
podman-compose up -d

# View logs
podman-compose logs -f
```

### 5. Verify Deployment

```bash
# Run security audit
./scripts/security-audit.sh --verbose

# Test HTTPS endpoint
curl -k https://localhost:8443/health

# Test with authentication
curl -k -u admin:your-password https://localhost:8443/api/tags
```

## GPU Configuration

GPU support is provided through compose override files. Use the appropriate command for your hardware:

```bash
# Detect your GPU and get recommendations
make detect-gpu

# CPU only (no GPU)
make up

# NVIDIA GPU (with nvidia-container-toolkit)
make up-nvidia

# NVIDIA GPU (direct passthrough, no toolkit required)
make up-nvidia-direct

# AMD GPU (ROCm)
make up-amd
```

### NVIDIA GPU

**Option 1: With NVIDIA Container Toolkit (Recommended)**

```bash
# Install NVIDIA drivers (if not already installed)
# Fedora/RHEL
sudo dnf install akmod-nvidia

# Install NVIDIA Container Toolkit
sudo dnf install nvidia-container-toolkit   # Fedora/RHEL
sudo apt install nvidia-container-toolkit   # Debian/Ubuntu

# Generate CDI specification for Podman
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

# Verify setup
nvidia-ctk cdi list

# Start with NVIDIA GPU
make up-nvidia
```

**Option 2: Direct Device Passthrough (No Toolkit)**

If you can't install the container toolkit, use direct passthrough:

```bash
# Verify NVIDIA devices exist
ls -la /dev/nvidia*

# Start with direct passthrough
make up-nvidia-direct
```

Edit `compose.nvidia-direct.yml` to add more GPUs if needed.

### AMD GPU (ROCm)

```bash
# Install ROCm drivers
# See: https://rocm.docs.amd.com/

# Add user to required groups
sudo usermod -aG render,video $USER
# Log out and back in

# Verify ROCm installation
rocminfo

# Check your GPU's GFX version
rocminfo | grep gfx

# Start with AMD GPU
make up-amd
```

**GFX Version Override**

For GPUs not officially supported, set `HSA_OVERRIDE_GFX_VERSION` in `.env`:

```bash
# RX 6000 series (RDNA2)
HSA_OVERRIDE_GFX_VERSION=10.3.0

# RX 7000 series (RDNA3) - usually auto-detected
# HSA_OVERRIDE_GFX_VERSION=11.0.0
```

### Multiple GPUs

**NVIDIA:** Set in `.env`:
```bash
NVIDIA_VISIBLE_DEVICES=0,1    # Specific GPUs
NVIDIA_VISIBLE_DEVICES=all    # All GPUs
```

**AMD:** Set in `.env`:
```bash
ROCR_VISIBLE_DEVICES=0,1      # Specific GPUs
ROCR_VISIBLE_DEVICES=all      # All GPUs
```

## Authentication

### HTTP Basic Auth

Set in `.env`:
```bash
AUTH_ENABLED=true
AUTH_USER=admin
AUTH_PASSWORD=your-secure-password
```

Access:
```bash
curl -k -u admin:your-secure-password https://localhost:8443/api/tags
```

### API Token Auth

Set in `.env`:
```bash
AUTH_ENABLED=true
API_TOKEN=your-secure-token-here
AUTH_PASSWORD=  # Leave empty
```

Access:
```bash
curl -k -H "Authorization: Bearer your-secure-token-here" \
  https://localhost:8443/api/tags
```

## IP Whitelist

The IP whitelist provides an additional security layer by restricting access to only approved IP addresses or ranges. This is strongly recommended for ITAR compliance.

### Enable Whitelist

Set in `.env`:
```bash
# Enable the whitelist
WHITELIST_ENABLED=true

# Comma-separated list of allowed IPs/CIDRs
WHITELIST_IPS=192.168.1.0/24,10.0.0.0/8,172.16.0.100
```

### Supported Formats

| Format | Example | Description |
|--------|---------|-------------|
| Single IPv4 | `192.168.1.100` | Single host |
| IPv4 CIDR | `192.168.1.0/24` | Subnet (256 hosts) |
| IPv4 CIDR | `10.0.0.0/8` | Large network |
| Single IPv6 | `2001:db8::1` | Single IPv6 host |
| IPv6 CIDR | `2001:db8::/32` | IPv6 subnet |

### Default Allowed

These are always whitelisted automatically:
- `127.0.0.1` / `::1` - Localhost
- `172.28.0.0/24` - Container internal network

### Testing Whitelist

```bash
# From whitelisted IP - should succeed
curl -k https://ollama-server:8443/health

# From non-whitelisted IP - returns 403 Forbidden
curl -k https://ollama-server:8443/health
# {"error": "Forbidden - IP not whitelisted", "client_ip": "203.0.113.50"}
```

### Combining with Authentication

For maximum security (recommended for ITAR), enable both:

```bash
# .env configuration
AUTH_ENABLED=true
AUTH_PASSWORD=your-secure-password
WHITELIST_ENABLED=true
WHITELIST_IPS=192.168.1.0/24
```

This creates defense in depth:
1. IP must be on whitelist (network layer)
2. Valid credentials required (application layer)
3. TLS 1.3 encryption (transport layer)

## Directory Structure

```
ollama-rag-vectordb/
├── certs/                    # SSL certificates (generated)
│   ├── ca.crt               # CA certificate
│   ├── ca.key               # CA private key
│   ├── server.crt           # Server certificate
│   ├── server.key           # Server private key
│   ├── server-chain.crt     # Certificate chain
│   └── dhparam.pem          # DH parameters
├── data/                     # Persistent data
│   ├── models/              # Ollama models
│   └── logs/                # Service logs
├── nginx/                    # Nginx proxy
│   ├── Dockerfile
│   ├── nginx.conf
│   ├── auth.conf.template
│   ├── ip-whitelist.conf.template
│   ├── whitelist-check.conf.template
│   └── docker-entrypoint.sh
├── scripts/
│   ├── generate-certs.sh    # Certificate generator
│   └── security-audit.sh    # Security checker
├── .env.example             # Configuration template
├── podman-compose.yml       # Container orchestration
└── README.md
```

## ITAR Compliance Checklist

- [ ] TLS 1.3 encryption enabled
- [ ] 4096-bit RSA keys for certificates
- [ ] Authentication enabled and configured
- [ ] IP whitelist enabled and configured
- [ ] Network isolation verified
- [ ] Non-root container execution
- [ ] Security audit passing
- [ ] Log retention configured
- [ ] Physical server in US territory
- [ ] Access limited to US persons
- [ ] Audit trail maintained

## Troubleshooting

### Certificate Issues

```bash
# Verify certificate chain
openssl verify -CAfile certs/ca.crt certs/server.crt

# Check certificate details
openssl x509 -in certs/server.crt -noout -text

# Test SSL connection
openssl s_client -connect localhost:8443 -servername localhost
```

### Container Issues

```bash
# Check container status
podman-compose ps

# View container logs
podman-compose logs ollama
podman-compose logs nginx-proxy

# Inspect container
podman inspect ollama-server
```

### GPU Issues

```bash
# Verify GPU visibility in container
podman exec ollama-server nvidia-smi

# Check Ollama GPU usage
podman exec ollama-server ollama list
```

## Security Recommendations

1. **Regular Certificate Rotation** - Renew certificates before expiration
2. **Strong Passwords** - Use 20+ character passwords with mixed characters
3. **Enable IP Whitelist** - Restrict access to known IP ranges only
4. **Network Segmentation** - Deploy on isolated network segment
5. **Log Monitoring** - Implement SIEM for security log analysis
6. **Regular Audits** - Run `security-audit.sh` before deployments
7. **Model Verification** - Validate model integrity before deployment
8. **Backup Strategy** - Securely backup models and configurations
9. **Principle of Least Privilege** - Use narrowest CIDR ranges in whitelist

## License

Internal use only. Not for distribution outside authorized personnel.

## Support

For security concerns or compliance questions, contact the AI Infrastructure Team.
