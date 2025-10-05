# Configuration Reference

Wraith uses TOML for configuration, providing a clean and readable alternative to nginx's configuration syntax.

## Server Configuration

### Basic Server Settings

```toml
[server]
# Listen addresses for HTTP
listen = ["0.0.0.0:80", "[::]:80"]

# Listen addresses for HTTPS
listen_tls = ["0.0.0.0:443", "[::]:443"]

# Number of worker threads (0 = auto-detect CPU cores)
worker_threads = 0

# Maximum concurrent connections per worker
max_connections = 10000

# Connection timeout
timeout = "30s"

# Keepalive timeout
keepalive_timeout = "75s"

# Maximum request body size
max_body_size = "10MB"
```

## TLS Configuration

### Certificate Settings

```toml
[tls]
# TLS version support
min_version = "1.3"
max_version = "1.3"

# Certificate and key paths
cert = "/etc/wraith/certs/server.crt"
key = "/etc/wraith/certs/server.key"

# Multiple certificates (SNI support)
[[tls.certificates]]
cert = "/etc/wraith/certs/example.com.crt"
key = "/etc/wraith/certs/example.com.key"
domains = ["example.com", "*.example.com"]

[[tls.certificates]]
cert = "/etc/wraith/certs/api.example.com.crt"
key = "/etc/wraith/certs/api.example.com.key"
domains = ["api.example.com"]

# Cipher suites (TLS 1.3)
cipher_suites = [
    "TLS_AES_256_GCM_SHA384",
    "TLS_CHACHA20_POLY1305_SHA256",
    "TLS_AES_128_GCM_SHA256",
]

# ACME/Let's Encrypt
[tls.acme]
enabled = true
email = "admin@example.com"
directory = "https://acme-v02.api.letsencrypt.org/directory"
# Staging: "https://acme-staging-v02.api.letsencrypt.org/directory"
```

## QUIC/HTTP3 Configuration

```toml
[quic]
enabled = true

# UDP port for QUIC (usually same as HTTPS port)
port = 443

# Connection settings
max_idle_timeout = "30s"
max_concurrent_streams = 100
initial_max_data = "10MB"
initial_max_stream_data_bidi_local = "1MB"
initial_max_stream_data_bidi_remote = "1MB"
initial_max_stream_data_uni = "1MB"

# Congestion control algorithm
congestion_control = "bbr"  # Options: cubic, bbr, reno

# Enable 0-RTT resumption
zero_rtt = true

# Post-quantum cryptography
[quic.pqc]
enabled = true
algorithm = "kyber768"  # Options: kyber512, kyber768, kyber1024

[http3]
enabled = true
# Enable HTTP/3 priority
priority_enabled = true
```

## Upstream Configuration

### Defining Upstreams

```toml
# Simple upstream
[[upstreams]]
name = "backend"
servers = ["http://localhost:8080"]

# Load balanced upstream with health checks
[[upstreams]]
name = "api_servers"
servers = [
    "http://10.0.1.10:8080",
    "http://10.0.1.11:8080",
    "http://10.0.1.12:8080",
]

# Load balancing algorithm
# Options: round_robin, least_conn, ip_hash, random, weighted
balance = "least_conn"

# Weighted load balancing
[[upstreams]]
name = "weighted_backend"
balance = "weighted"

[[upstreams.server]]
addr = "http://10.0.1.10:8080"
weight = 3  # Gets 3x more traffic

[[upstreams.server]]
addr = "http://10.0.1.11:8080"
weight = 1

# Health check configuration
[upstreams.health_check]
enabled = true
interval = "10s"
timeout = "5s"
path = "/health"
expected_status = 200
healthy_threshold = 2    # Consecutive successes to mark healthy
unhealthy_threshold = 3  # Consecutive failures to mark unhealthy

# Connection settings
[upstreams.connection]
max_idle = 100          # Max idle connections to keep
max_idle_per_host = 10  # Max idle connections per host
timeout = "30s"         # Connection timeout
keepalive = "60s"       # Keepalive duration
```

## Routing Configuration

### Route Definitions

```toml
# Simple path-based routing
[[routes]]
path = "/"
upstream = "backend"

# Regex pattern matching
[[routes]]
path = "^/api/v[0-9]+/.*"
regex = true
upstream = "api_servers"

# Host-based routing
[[routes]]
host = "api.example.com"
path = "/"
upstream = "api_servers"

# Multiple conditions
[[routes]]
host = "admin.example.com"
path = "/dashboard"
upstream = "admin_backend"
methods = ["GET", "POST"]

# Path rewriting
[[routes]]
path = "^/old/(.*)"
regex = true
upstream = "backend"
rewrite = "/new/$1"

# Header-based routing
[[routes]]
path = "/"
upstream = "api_v2"

[[routes.headers]]
name = "X-API-Version"
value = "2.0"

# Request/response modifications
[routes.headers_add]
X-Proxy-By = "Wraith"
X-Request-ID = "${request_id}"

[routes.headers_remove]
request = ["X-Internal-Secret"]
response = ["Server", "X-Powered-By"]
```

## Logging Configuration

### Log Settings

```toml
[logging]
# Log level: debug, info, warn, error
level = "info"

# Log format: json, text, logfmt
format = "json"

# Log output: stdout, stderr, file, syslog, sqlite
output = "stdout"

# File output settings
[logging.file]
path = "/var/log/wraith/access.log"
max_size = "100MB"
max_backups = 10
max_age = "30d"
compress = true

# SQLite logging for queryable logs
[logging.sqlite]
enabled = true
path = "/var/lib/wraith/logs.db"
# Retention policy
max_rows = 1000000
max_age = "90d"

# Fields to log
fields = [
    "timestamp",
    "method",
    "path",
    "status",
    "duration_ms",
    "bytes_sent",
    "client_ip",
    "user_agent",
    "upstream",
    "upstream_duration_ms",
]

# Syslog output
[logging.syslog]
enabled = false
address = "localhost:514"
facility = "local0"
tag = "wraith"
```

## Security Configuration

### Rate Limiting

```toml
[rate_limit]
enabled = true

# Global rate limit
requests_per_second = 1000
burst = 2000

# Per-IP rate limit
[rate_limit.per_ip]
enabled = true
requests_per_second = 100
burst = 200

# Per-route rate limits
[[routes]]
path = "/api/auth/login"
upstream = "auth_backend"

[routes.rate_limit]
requests_per_second = 10
burst = 20
```

### CORS Settings

```toml
[cors]
enabled = true
allowed_origins = ["https://example.com", "https://app.example.com"]
allowed_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
allowed_headers = ["Authorization", "Content-Type", "X-API-Key"]
expose_headers = ["X-Request-ID"]
max_age = "3600s"
allow_credentials = true
```

### Security Headers

```toml
[security]
# Add security headers to all responses
[security.headers]
X-Frame-Options = "DENY"
X-Content-Type-Options = "nosniff"
X-XSS-Protection = "1; mode=block"
Strict-Transport-Security = "max-age=31536000; includeSubDomains"
Content-Security-Policy = "default-src 'self'"
Referrer-Policy = "strict-origin-when-cross-origin"
Permissions-Policy = "geolocation=(), microphone=(), camera=()"
```

### Zero-Trust Integrations

```toml
# CrowdSec integration
[crowdsec]
enabled = true
lapi_url = "http://localhost:8080"
api_key = "${CROWDSEC_API_KEY}"
# Bouncer mode: live, stream
mode = "live"

# Wazuh integration
[wazuh]
enabled = true
manager_url = "https://wazuh.example.com:55000"
api_user = "wraith"
api_password = "${WAZUH_PASSWORD}"
agent_id = "001"

# Tailscale integration
[tailscale]
enabled = true
# Restrict access to Tailscale network only
restrict_to_tailnet = true
# Allowed Tailscale users
allowed_users = ["alice@example.com", "bob@example.com"]
```

## Compression

```toml
[compression]
enabled = true

# Compression algorithms (in preference order)
algorithms = ["br", "gzip"]  # br = brotli

# Brotli settings
[compression.brotli]
level = 6  # 0-11, higher = better compression, slower

# Gzip settings
[compression.gzip]
level = 6  # 1-9, higher = better compression, slower

# MIME types to compress
mime_types = [
    "text/html",
    "text/css",
    "text/javascript",
    "application/javascript",
    "application/json",
    "application/xml",
    "text/xml",
    "image/svg+xml",
]

# Minimum size to compress
min_size = "1KB"
```

## Caching

```toml
[cache]
enabled = true

# Cache backend: memory, redis
backend = "memory"

# Memory cache settings
[cache.memory]
max_size = "1GB"
# Eviction policy: lru, lfu, fifo
eviction = "lru"

# Redis cache settings
[cache.redis]
url = "redis://localhost:6379/0"
pool_size = 10
timeout = "5s"

# Cache rules
[[cache.rules]]
path = "^/static/.*"
ttl = "1h"
vary = ["Accept-Encoding"]

[[cache.rules]]
path = "^/api/.*"
ttl = "5m"
methods = ["GET"]
```

## Example Complete Configuration

```toml
[server]
listen = ["0.0.0.0:80"]
listen_tls = ["0.0.0.0:443"]
worker_threads = 0

[tls]
cert = "/etc/wraith/certs/server.crt"
key = "/etc/wraith/certs/server.key"

[tls.acme]
enabled = true
email = "admin@example.com"

[[upstreams]]
name = "backend"
servers = ["http://localhost:8080"]

[upstreams.health_check]
enabled = true
interval = "10s"
path = "/health"

[[routes]]
path = "/"
upstream = "backend"

[logging]
level = "info"
format = "json"

[logging.sqlite]
enabled = true
path = "/var/lib/wraith/logs.db"
```

## Environment Variable Substitution

Configuration files support environment variable substitution using `${VAR_NAME}` syntax:

```toml
[tls.acme]
email = "${ADMIN_EMAIL}"

[database]
url = "${DATABASE_URL}"
password = "${DB_PASSWORD}"
```

## Configuration Validation

Test your configuration before deploying:

```bash
# Validate configuration file
wraith test -c wraith.toml

# Check syntax and upstream connectivity
wraith test -c wraith.toml --check-upstreams

# Dry run (don't actually start server)
wraith serve -c wraith.toml --dry-run
```
