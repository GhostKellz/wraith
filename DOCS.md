# Wraith Documentation

## 🔥 Modern QUIC/HTTP3 Reverse Proxy & Static Server

Wraith is a high-performance, security-focused reverse proxy and static file server built with Zig, designed for the modern web with native HTTP/3 and QUIC support.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Core Features](#core-features)
- [Configuration](#configuration)
- [Security Features](#security-features)
- [Performance Features](#performance-features)
- [API Reference](#api-reference)
- [Deployment](#deployment)
- [Monitoring](#monitoring)

---

## 🌟 Overview

### Key Highlights

- **HTTP/3 First**: Native QUIC transport with zero TCP dependency
- **TLS 1.3 Only**: Hardened cryptographic security with post-quantum readiness
- **Built with Zig**: Maximum performance with memory safety
- **Modern Architecture**: Declarative configuration, zero-downtime reloads
- **Enterprise Security**: Rate limiting, DDoS protection, WAF integration ready

### Protocol Stack

```
┌─────────────────┐
│     HTTP/3      │ ← Application Layer
├─────────────────┤
│      QUIC       │ ← Transport Layer (UDP-based)
├─────────────────┤
│    TLS 1.3      │ ← Security Layer
├─────────────────┤
│   IPv6/IPv4     │ ← Network Layer
└─────────────────┘
```

---

## 🏗️ Architecture

### Core Libraries Integration

Wraith is built on three foundational libraries:

- **zquic**: HTTP/3 and QUIC protocol implementation
- **zcrypto**: Cryptographic primitives and TLS management  
- **tokioZ**: Async runtime for high-performance I/O

### Module Structure

```
src/
├── main.zig           # CLI entry point
├── root.zig           # Library exports
├── server.zig         # HTTP/3 server core
├── config.zig         # TOML configuration parser
├── router.zig         # Smart routing system
├── proxy.zig          # Reverse proxy with load balancing
├── tls.zig           # TLS certificate management
├── rate_limiter.zig  # Rate limiting & DDoS protection
└── static.zig        # Static file server
```

---

## ⭐ Core Features

### 1. HTTP/3 Server (`server.zig`)

**Implementation**: Full HTTP/3 server with QUIC transport using `zquic`

**Features**:
- Native QUIC connection handling
- HTTP/3 frame parsing and generation
- Connection multiplexing
- Stream management
- Graceful shutdown
- IPv6-first with IPv4 fallback

**Code Example**:
```zig
var server = try WraithServer.init(allocator, config);
defer server.deinit();

try server.start(); // Starts HTTP/3 server on configured port
```

### 2. TOML Configuration Parser (`config.zig`)

**Implementation**: Custom TOML parser for declarative configuration

**Supported Sections**:
- `[server]` - Server binding and connection settings
- `[tls]` - TLS certificate and security configuration  
- `[proxy]` - Reverse proxy and upstream settings
- `[static_files]` - Static file serving configuration
- `[security]` - Rate limiting and DDoS protection

**Example Configuration**:
```toml
[server]
bind_address = "::"
port = 443
max_connections = 10000
enable_http3 = true

[tls]
auto_cert = true
min_version = "tls13"
alpn = ["h3", "h3-32"]

[static_files]
enabled = true
root = "./public"
compression = true
cache_control = "public, max-age=3600"

[security.rate_limiting]
enabled = true
requests_per_minute = 60
burst = 10
```

### 3. Smart Routing System (`router.zig`)

**Implementation**: Advanced HTTP routing with pattern matching

**Features**:
- Host-based routing (`api.example.com` vs `www.example.com`)
- Path pattern matching (`/users/:id`, `/api/*`)
- HTTP method filtering (`GET`, `POST`, etc.)
- Route priorities (0-255, higher = more priority)
- Parameter extraction
- Middleware support
- Built-in health endpoints

**Usage**:
```zig
var router = Router.init(allocator);

// Add parameterized route
try router.addRoute(.{
    .path = "/users/:id",
    .method = .GET,
    .handler = getUserHandler,
    .priority = 100,
});

// Add wildcard route
try router.addRoute(.{
    .path = "/api/*",
    .host = "api.example.com",
    .handler = apiHandler,
    .route_type = .api,
});
```

### 4. Reverse Proxy with Load Balancing (`proxy.zig`)

**Implementation**: HTTP/3 reverse proxy using `zquic` client connections

**Load Balancing Algorithms**:
- **Round Robin**: Equal distribution across upstreams
- **Least Connections**: Routes to upstream with fewest active connections
- **IP Hash**: Consistent routing based on client IP
- **Weighted**: Distribution based on upstream weights
- **Random**: Random selection for even distribution

**Health Checking**:
- Configurable health check intervals
- HTTP status code validation
- Automatic upstream marking (healthy/unhealthy)
- Failure threshold and timeout configuration
- Graceful upstream recovery

**Features**:
- Connection pooling
- Request statistics tracking
- Hop-by-hop header filtering
- Proxy headers injection
- Upstream failover
- Circuit breaker pattern

**Configuration**:
```toml
[proxy]
enabled = true
load_balancing = "least_connections"

[[proxy.upstreams]]
name = "backend1"
address = "127.0.0.1"
port = 8080
weight = 2
max_fails = 3
fail_timeout = 30

[[proxy.upstreams]]
name = "backend2" 
address = "127.0.0.1"
port = 8081
weight = 1

[proxy.health_check]
enabled = true
interval = 10
path = "/health"
expected_status = 200
```

### 5. TLS Certificate Management (`tls.zig`)

**Implementation**: Certificate management using `zcrypto` cryptographic primitives

**Features**:
- **Ed25519** key pair generation (modern, fast, secure)
- Self-signed certificate generation for development
- X.509 certificate parsing and validation
- ACME/Let's Encrypt integration framework
- Certificate signing request (CSR) generation
- PEM encoding/decoding
- Certificate chain validation

**TLS 1.3 Security**:
- **Cipher Suites**: AES-256-GCM, ChaCha20-Poly1305, AES-128-GCM
- **Signature Algorithms**: Ed25519, ECDSA (P-256, P-384), RSA-PSS
- **Named Groups**: X25519, secp256r1, secp384r1, X448
- **ALPN**: h3, h3-32, h3-31 (HTTP/3 negotiation)

**Certificate Generation**:
```zig
var tls_config = TlsConfig.init(allocator);
try tls_config.generateSelfSignedCert("localhost");

// Certificate includes:
// - Subject Alternative Names (DNS + IP)
// - Key Usage extensions
// - Extended Key Usage for TLS server auth
// - 1-year validity period
```

### 6. Rate Limiting & DDoS Protection (`rate_limiter.zig`)

**Implementation**: Multi-layer security using token bucket and sliding window algorithms

**Rate Limiting**:
- **Token Bucket Algorithm**: Smooth rate limiting with burst capability
- **Per-client limits**: Individual IP-based rate limiting
- **Global limits**: Server-wide request rate protection
- **Request size limits**: Protection against large payload attacks

**DDoS Protection**:
- **Connection rate limiting**: Max connections per IP
- **Packet rate limiting**: Packet-per-second thresholds
- **Sliding window tracking**: Time-based rate calculations
- **Automatic blocking**: Temporary IP blocking for violations

**Security Features**:
- IP whitelist/blacklist support
- **zcrypto** secure hashing for IP tracking
- Configurable block durations
- Statistics and monitoring
- Memory-efficient cleanup of expired entries

**Configuration**:
```toml
[security.rate_limiting]
enabled = true
requests_per_minute = 60
burst = 10
max_request_size = 1048576  # 1MB
auto_block_enabled = true
block_duration = 300        # 5 minutes

[security.ddos_protection]
enabled = true
max_connections_per_ip = 100
connection_rate_limit = 10
packet_rate_limit = 1000
window_size = 60
```

### 7. Advanced Static File Server (`static.zig`)

**Implementation**: High-performance static file serving with caching and compression

**Caching System**:
- **In-memory file cache** with mtime validation
- **ETag generation** using `zcrypto` SHA-256 hashing
- **HTTP cache headers**: Cache-Control, ETag, Last-Modified
- **Conditional requests**: If-Modified-Since, If-None-Match support

**Compression**:
- **Gzip compression** for compressible content types
- Configurable compression types (HTML, CSS, JS, JSON, etc.)
- Content-Encoding header management
- Automatic compression selection

**Security Features**:
- **Directory traversal protection** with path sanitization
- **MIME type detection** with comprehensive mapping
- **Security headers**: X-Content-Type-Options, X-Frame-Options
- **Index file serving**: index.html, index.htm support
- **Directory listing** (optional, disabled by default)

**MIME Type Support**:
```
HTML/CSS: text/html, text/css
JavaScript: application/javascript  
Images: image/png, image/jpeg, image/gif, image/svg+xml
Fonts: font/woff, font/woff2, font/ttf
Documents: application/pdf, text/plain
```

**Performance**:
- File caching with automatic invalidation
- Compressed content caching
- ETag-based client caching
- Memory usage tracking
- Cache statistics

---

## ⚙️ Configuration

### Configuration File Structure

Wraith uses TOML configuration files with the following structure:

```toml
# Server configuration
[server]
bind_address = "::"          # IPv6 bind-all
port = 443                   # HTTPS/HTTP3 port
workers = 0                  # Auto-detect CPU cores
max_connections = 10000      # Connection limit
enable_http3 = true          # Enable HTTP/3
enable_http2 = false         # Disable HTTP/2  
enable_http1 = false         # Disable HTTP/1.1

# TLS configuration
[tls]
auto_cert = true             # ACME integration
min_version = "tls13"        # TLS 1.3 only
max_version = "tls13"
alpn = ["h3", "h3-32"]      # HTTP/3 ALPN

# Static file serving
[static_files]
enabled = true
root = "./public"
compression = true
cache_control = "public, max-age=3600"
etag = true
autoindex = false           # Directory listing

# Security configuration
[security.rate_limiting]
enabled = true
requests_per_minute = 60
burst = 10
whitelist = ["127.0.0.1", "::1"]
blacklist = []

[security.headers]
hsts = true
hsts_max_age = 31536000
csp = "default-src 'self'"
x_frame_options = "DENY"

# Reverse proxy (optional)
[proxy]
enabled = false
load_balancing = "round_robin"

[[proxy.upstreams]]
name = "backend1"
address = "127.0.0.1" 
port = 8080
weight = 1

[proxy.health_check]
enabled = true
interval = 10
path = "/health"
expected_status = 200
```

### Environment Variables

Wraith supports environment variable overrides:

```bash
WRAITH_PORT=8443
WRAITH_CONFIG_FILE=custom.toml
WRAITH_LOG_LEVEL=debug
WRAITH_TLS_AUTO_CERT=true
```

---

## 🛡️ Security Features

### TLS/Cryptographic Security

- **TLS 1.3 Only**: Modern cryptographic protocols
- **Post-Quantum Ready**: X25519, Ed25519 algorithms  
- **Perfect Forward Secrecy**: Ephemeral key exchange
- **HSTS**: HTTP Strict Transport Security
- **Certificate Transparency**: ACME integration ready

### Application Security

- **Rate Limiting**: Token bucket algorithm
- **DDoS Protection**: Multi-layer traffic analysis
- **Path Traversal Protection**: Sanitized file paths
- **Security Headers**: Comprehensive header set
- **IP Filtering**: Whitelist/blacklist support

### Input Validation

- **Request Size Limits**: Configurable payload limits
- **Path Sanitization**: Directory traversal prevention
- **Header Validation**: Malformed request protection
- **Content Type Validation**: MIME type verification

---

## 🚀 Performance Features

### Networking Performance

- **QUIC Transport**: Zero-RTT connection establishment
- **Connection Multiplexing**: Multiple streams per connection
- **UDP-based**: No TCP head-of-line blocking
- **IPv6 First**: Modern network stack

### Caching & Compression

- **In-Memory Caching**: Hot file caching
- **Gzip Compression**: Bandwidth optimization
- **ETag Support**: Client-side caching
- **Cache Control**: Flexible cache policies

### Memory Management

- **Zig Allocators**: Precise memory control
- **Zero-Copy Operations**: Efficient data handling
- **Connection Pooling**: Resource reuse
- **Automatic Cleanup**: Memory leak prevention

### Load Balancing

- **Multiple Algorithms**: Choose optimal distribution
- **Health Monitoring**: Automatic failover
- **Connection Tracking**: Real-time statistics
- **Circuit Breaker**: Fault tolerance

---

## 📖 API Reference

### Server Management

```zig
// Initialize server
var server = try WraithServer.init(allocator, config);
defer server.deinit();

// Start serving
try server.start();

// Stop server
server.stop();
```

### Router Configuration

```zig
// Create router
var router = try createDefaultRouter(allocator);

// Add custom route
try router.addRoute(.{
    .path = "/api/users/:id",
    .method = .GET,
    .handler = handleGetUser,
    .priority = 100,
});

// Match request
if (router.match(request)) |match| {
    const response = try match.route.handler(request, match.params);
}
```

### Rate Limiting

```zig
// Initialize rate limiter
var limiter = RateLimiter.init(allocator, config);

// Check request
const result = try limiter.isAllowed(client_ip, request_size);
if (!result.allowed) {
    // Rate limited - return 429 Too Many Requests
}
```

### Static File Serving

```zig
// Initialize static server
var static_server = try StaticFileServer.init(allocator, config);

// Serve file
const response = try static_server.serveFile(path, headers);
```

---

## 🚀 Deployment

### CLI Usage

```bash
# Start server with default configuration
wraith serve

# Start with custom config
wraith serve -c production.toml

# Development mode with self-signed certs
wraith serve --dev

# Generate certificates
wraith generate certs --dns

# Check server status
wraith status

# Show version
wraith version
```

### Production Deployment

#### Docker Deployment

```dockerfile
FROM alpine:latest

# Install dependencies
RUN apk add --no-cache ca-certificates

# Copy wraith binary
COPY wraith /usr/local/bin/
COPY wraith.toml /etc/wraith/
COPY public/ /var/www/

# Expose port
EXPOSE 443/udp

# Run server
CMD ["wraith", "serve", "-c", "/etc/wraith/wraith.toml"]
```

#### Systemd Service

```ini
[Unit]
Description=Wraith HTTP/3 Server
After=network.target

[Service]
Type=simple
User=wraith
Group=wraith
ExecStart=/usr/local/bin/wraith serve -c /etc/wraith/wraith.toml
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Load Balancer Configuration

```toml
[proxy]
enabled = true
load_balancing = "least_connections"

# Production backends
[[proxy.upstreams]]
name = "app1"
address = "10.0.1.10"
port = 8080
weight = 2

[[proxy.upstreams]]
name = "app2" 
address = "10.0.1.11"
port = 8080
weight = 2

[[proxy.upstreams]]
name = "app3-backup"
address = "10.0.1.12"
port = 8080
weight = 1
backup = true

[proxy.health_check]
enabled = true
interval = 5
timeout = 3
path = "/health"
expected_status = 200
```

---

## 📊 Monitoring

### Built-in Endpoints

- `GET /health` - Health check endpoint
- `GET /status` - Server status and statistics

### Statistics Available

#### Server Statistics
- Active connections
- Total requests processed
- Uptime
- Memory usage

#### Rate Limiting Statistics
- Active clients
- Blocked clients  
- Global tokens remaining
- Total blocks issued

#### Proxy Statistics
- Upstream health status
- Request distribution
- Response times
- Error rates

#### Static File Statistics
- Cached files count
- Cache memory usage
- Cache hit ratio
- Compression ratio

### Example Monitoring Integration

```bash
# Health check
curl -H "accept: application/json" https://localhost/health

# Detailed status
curl -H "accept: application/json" https://localhost/status

# Prometheus metrics (when integrated)
curl https://localhost/metrics
```

---

## 🔧 Development

### Building from Source

```bash
# Clone repository
git clone https://github.com/ghostkellz/wraith.git
cd wraith

# Build with Zig
zig build

# Run tests
zig build test

# Development mode
zig build run -- serve --dev
```

### Testing

```bash
# Unit tests
zig build test

# Integration tests
zig build test-integration

# Performance tests
zig build bench
```

### Extending Wraith

#### Custom Route Handlers

```zig
fn customHandler(request: *const RoutingRequest, params: ?std.StringHashMap([]const u8)) !RouteResponse {
    var headers = std.StringHashMap([]const u8).init(allocator);
    try headers.put("content-type", "application/json");
    
    return RouteResponse{
        .status = 200,
        .body = "{\"message\": \"Custom response\"}",
        .headers = headers,
    };
}
```

#### Custom Middleware

```zig
fn authMiddleware(request: *RoutingRequest, next: *const fn() anyerror!RouteResponse) !RouteResponse {
    // Validate authentication
    if (request.headers.get("authorization") == null) {
        return RouteResponse{
            .status = 401,
            .body = "Unauthorized",
            .headers = std.StringHashMap([]const u8).init(allocator),
        };
    }
    
    // Continue to next handler
    return try next();
}
```

---

## 📚 Additional Resources

### Performance Tuning

- **Connection Limits**: Adjust `max_connections` based on server capacity
- **Worker Threads**: Set `workers = 0` for auto-detection
- **Cache Settings**: Tune cache sizes for optimal memory usage
- **Compression**: Enable for text-based content types

### Security Hardening

- **Rate Limits**: Set conservative limits for production
- **TLS Configuration**: Use only TLS 1.3 with strong ciphers
- **Headers**: Enable all security headers
- **Access Control**: Use whitelist/blacklist for critical endpoints

### Troubleshooting

- **Debug Logging**: Set `WRAITH_LOG_LEVEL=debug`
- **Health Checks**: Monitor `/health` endpoint
- **Statistics**: Use `/status` for operational insights
- **Certificate Issues**: Check `wraith generate certs` output

---

## 📄 License

Wraith is released under the MIT License. See [LICENSE](LICENSE) for details.

---

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

**Built with ❤️ using Zig, zquic, zcrypto, and tokioZ**