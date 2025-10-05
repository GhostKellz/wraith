# Deployment Guide

This guide covers deploying Wraith in production environments using various methods.

## Binary Installation

### From Release

Download the latest release for your platform:

```bash
# Linux x86_64
wget https://github.com/yourusername/wraith/releases/latest/download/wraith-linux-x86_64.tar.gz
tar xzf wraith-linux-x86_64.tar.gz
sudo mv wraith /usr/local/bin/
sudo chmod +x /usr/local/bin/wraith

# Verify installation
wraith version
```

### From Source

Build from source with Zig 0.16.0-dev:

```bash
# Clone repository
git clone https://github.com/yourusername/wraith.git
cd wraith

# Build release binary
zig build -Doptimize=ReleaseFast

# Install
sudo cp zig-out/bin/wraith /usr/local/bin/
```

## Package Managers

### Arch Linux (AUR)

```bash
# Using yay
yay -S wraith

# Using paru
paru -S wraith

# Manual installation
git clone https://aur.archlinux.org/wraith.git
cd wraith
makepkg -si
```

### Debian/Ubuntu

```bash
# Add repository
curl -fsSL https://wraith-proxy.com/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/wraith.gpg
echo "deb [signed-by=/usr/share/keyrings/wraith.gpg] https://wraith-proxy.com/apt stable main" | sudo tee /etc/apt/sources.list.d/wraith.list

# Install
sudo apt update
sudo apt install wraith
```

### Homebrew (macOS/Linux)

```bash
brew install wraith
```

## Docker Deployment

### Using Official Image

```bash
# Pull image
docker pull wraith/wraith:latest

# Run container
docker run -d \
  --name wraith \
  -p 80:80 \
  -p 443:443 \
  -v /path/to/wraith.toml:/etc/wraith/wraith.toml:ro \
  -v /path/to/certs:/etc/wraith/certs:ro \
  wraith/wraith:latest
```

### Docker Compose

```yaml
version: '3.8'

services:
  wraith:
    image: wraith/wraith:latest
    container_name: wraith
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"  # QUIC/HTTP3
    volumes:
      - ./wraith.toml:/etc/wraith/wraith.toml:ro
      - ./certs:/etc/wraith/certs:ro
      - wraith-logs:/var/log/wraith
      - wraith-data:/var/lib/wraith
    environment:
      - WRAITH_LOG_LEVEL=info
      - ACME_EMAIL=admin@example.com
    networks:
      - proxy
    healthcheck:
      test: ["CMD", "wraith", "status"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Backend service example
  backend:
    image: your-app:latest
    networks:
      - proxy

volumes:
  wraith-logs:
  wraith-data:

networks:
  proxy:
    driver: bridge
```

### Multi-Stage Dockerfile

```dockerfile
# Build stage
FROM ghcr.io/ziglang/zig:0.16.0 AS builder

WORKDIR /build
COPY . .

RUN zig build -Doptimize=ReleaseFast

# Runtime stage
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy binary
COPY --from=builder /build/zig-out/bin/wraith /usr/local/bin/wraith

# Create directories
RUN mkdir -p /etc/wraith /var/log/wraith /var/lib/wraith

# Non-root user
RUN useradd -r -s /bin/false wraith && \
    chown -R wraith:wraith /var/log/wraith /var/lib/wraith

USER wraith

EXPOSE 80 443 443/udp

ENTRYPOINT ["/usr/local/bin/wraith"]
CMD ["serve", "-c", "/etc/wraith/wraith.toml"]
```

## Systemd Service

### Service File

Create `/etc/systemd/system/wraith.service`:

```ini
[Unit]
Description=Wraith Web Server and Reverse Proxy
Documentation=https://github.com/yourusername/wraith
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=wraith
Group=wraith

# Paths
ExecStart=/usr/local/bin/wraith serve -c /etc/wraith/wraith.toml
ExecReload=/bin/kill -HUP $MAINPID
ExecStop=/bin/kill -TERM $MAINPID

# Restart policy
Restart=always
RestartSec=10
TimeoutStopSec=30

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/wraith /var/lib/wraith

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

# Environment
Environment="WRAITH_LOG_LEVEL=info"
EnvironmentFile=-/etc/wraith/environment

[Install]
WantedBy=multi-user.target
```

### Setup and Management

```bash
# Create wraith user
sudo useradd -r -s /bin/false wraith

# Create directories
sudo mkdir -p /etc/wraith /var/log/wraith /var/lib/wraith
sudo chown -R wraith:wraith /var/log/wraith /var/lib/wraith

# Install service file
sudo systemctl daemon-reload
sudo systemctl enable wraith
sudo systemctl start wraith

# Check status
sudo systemctl status wraith

# View logs
sudo journalctl -u wraith -f

# Reload configuration
sudo systemctl reload wraith

# Stop service
sudo systemctl stop wraith
```

## Kubernetes Deployment

### Deployment Manifest

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wraith
  namespace: ingress
spec:
  replicas: 3
  selector:
    matchLabels:
      app: wraith
  template:
    metadata:
      labels:
        app: wraith
    spec:
      containers:
      - name: wraith
        image: wraith/wraith:latest
        ports:
        - name: http
          containerPort: 80
        - name: https
          containerPort: 443
        - name: quic
          containerPort: 443
          protocol: UDP
        volumeMounts:
        - name: config
          mountPath: /etc/wraith
          readOnly: true
        - name: certs
          mountPath: /etc/wraith/certs
          readOnly: true
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 1000m
            memory: 512Mi
        livenessProbe:
          exec:
            command: ["wraith", "status"]
          initialDelaySeconds: 10
          periodSeconds: 30
        readinessProbe:
          exec:
            command: ["wraith", "status"]
          initialDelaySeconds: 5
          periodSeconds: 10
      volumes:
      - name: config
        configMap:
          name: wraith-config
      - name: certs
        secret:
          secretName: wraith-tls
---
apiVersion: v1
kind: Service
metadata:
  name: wraith
  namespace: ingress
spec:
  type: LoadBalancer
  selector:
    app: wraith
  ports:
  - name: http
    port: 80
    targetPort: 80
  - name: https
    port: 443
    targetPort: 443
  - name: quic
    port: 443
    protocol: UDP
    targetPort: 443
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: wraith-config
  namespace: ingress
data:
  wraith.toml: |
    [server]
    listen = ["0.0.0.0:80"]
    listen_tls = ["0.0.0.0:443"]

    [[upstreams]]
    name = "backend"
    servers = ["http://backend-service:8080"]

    [[routes]]
    path = "/"
    upstream = "backend"
```

## TLS/SSL Certificates

### Let's Encrypt (ACME)

Wraith supports automatic certificate management:

```toml
[tls.acme]
enabled = true
email = "admin@example.com"
directory = "https://acme-v02.api.letsencrypt.org/directory"

# Domains to obtain certificates for
domains = [
    "example.com",
    "www.example.com",
    "api.example.com",
]

# Challenge type: http-01, dns-01
challenge = "http-01"

# Storage path for certificates
storage = "/var/lib/wraith/acme"
```

### Manual Certificates

```bash
# Generate self-signed certificate (development only)
openssl req -x509 -newkey rsa:4096 -nodes \
  -keyout /etc/wraith/certs/server.key \
  -out /etc/wraith/certs/server.crt \
  -days 365 \
  -subj "/CN=localhost"

# Set permissions
sudo chown wraith:wraith /etc/wraith/certs/*
sudo chmod 600 /etc/wraith/certs/*.key
sudo chmod 644 /etc/wraith/certs/*.crt
```

## High Availability Setup

### Load Balanced Wraith Cluster

```
                    ┌──────────────┐
                    │   DNS/GLB    │
                    └──────┬───────┘
                           │
              ┌────────────┴────────────┐
              │                         │
        ┌─────▼─────┐            ┌──────▼────┐
        │  Wraith 1 │            │ Wraith 2  │
        └─────┬─────┘            └──────┬────┘
              │                         │
              └────────────┬────────────┘
                           │
                    ┌──────▼───────┐
                    │   Upstreams  │
                    └──────────────┘
```

### Keepalived Configuration

```bash
# /etc/keepalived/keepalived.conf
vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1

    virtual_ipaddress {
        192.168.1.100
    }
}

vrrp_script chk_wraith {
    script "/usr/local/bin/wraith status"
    interval 2
    weight -5
}
```

## Monitoring and Observability

### Prometheus Metrics

Wraith exposes metrics at `/metrics`:

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'wraith'
    static_configs:
      - targets: ['localhost:9090']
    metrics_path: /metrics
```

### Grafana Dashboard

Import the official Wraith dashboard:

```bash
# Dashboard ID: wraith-proxy
curl -o wraith-dashboard.json https://grafana.com/api/dashboards/12345/revisions/1/download
```

### Log Aggregation

#### Loki

```yaml
# promtail.yml
clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: wraith
    static_configs:
      - targets:
          - localhost
        labels:
          job: wraith
          __path__: /var/log/wraith/*.log
```

#### ELK Stack

```bash
# Filebeat configuration
filebeat.inputs:
- type: log
  paths:
    - /var/log/wraith/access.log
  json.keys_under_root: true

output.elasticsearch:
  hosts: ["localhost:9200"]
```

## Security Hardening

### Firewall Rules

```bash
# UFW
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 443/udp  # QUIC

# iptables
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 443 -j ACCEPT
```

### SELinux Policy

```bash
# Allow wraith to bind to privileged ports
sudo semanage port -a -t http_port_t -p tcp 80
sudo semanage port -a -t http_port_t -p tcp 443

# Allow network connections
sudo setsebool -P httpd_can_network_connect 1
```

### AppArmor Profile

```
#include <tunables/global>

/usr/local/bin/wraith {
  #include <abstractions/base>
  #include <abstractions/nameservice>

  capability net_bind_service,
  capability setgid,
  capability setuid,

  /usr/local/bin/wraith mr,
  /etc/wraith/** r,
  /var/log/wraith/** rw,
  /var/lib/wraith/** rw,

  network inet stream,
  network inet dgram,
}
```

## Performance Tuning

### System Limits

```bash
# /etc/sysctl.conf
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
fs.file-max = 2097152

# Apply changes
sudo sysctl -p
```

### File Descriptors

```bash
# /etc/security/limits.conf
wraith soft nofile 65536
wraith hard nofile 65536

# Verify
ulimit -n
```

## Backup and Recovery

### Configuration Backup

```bash
# Backup script
#!/bin/bash
tar czf wraith-backup-$(date +%Y%m%d).tar.gz \
  /etc/wraith \
  /var/lib/wraith

# Store in S3
aws s3 cp wraith-backup-*.tar.gz s3://backups/wraith/
```

### Database Backup (SQLite Logs)

```bash
# Backup SQLite logs database
sqlite3 /var/lib/wraith/logs.db ".backup /backup/logs-$(date +%Y%m%d).db"
```

## Troubleshooting

### Common Issues

**Port already in use:**
```bash
# Find process using port
sudo lsof -i :80
sudo netstat -tulpn | grep :80

# Kill process or change Wraith port
```

**Permission denied:**
```bash
# Allow binding to privileged ports (< 1024)
sudo setcap 'cap_net_bind_service=+ep' /usr/local/bin/wraith
```

**Certificate errors:**
```bash
# Verify certificate
openssl x509 -in /etc/wraith/certs/server.crt -text -noout

# Check certificate/key pair
openssl x509 -noout -modulus -in cert.crt | openssl md5
openssl rsa -noout -modulus -in cert.key | openssl md5
```

### Debug Mode

```bash
# Enable debug logging
WRAITH_LOG_LEVEL=debug wraith serve -c wraith.toml

# Verbose output
wraith serve -c wraith.toml --verbose

# Dry run (validate without starting)
wraith serve -c wraith.toml --dry-run
```
