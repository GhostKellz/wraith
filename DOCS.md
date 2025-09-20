# Wraith Documentation

## 🔥 Modern HTTP Reverse Proxy & Static Server

Wraith is a high-performance, security-focused reverse proxy and static file server built with Rust, designed for modern web applications with advanced load balancing, health checking, and real-time monitoring.

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

- **HTTP/1.1 & HTTP/2**: Full protocol support with automatic negotiation
- **TLS 1.3**: Modern cryptography with Rustls
- **Built with Rust**: Memory safety and zero-cost abstractions
- **Modern Architecture**: Declarative TOML configuration, zero-downtime reloads
- **Production Ready**: Advanced load balancing, health checking, metrics

### Protocol Stack

```
┌─────────────────┐
│   HTTP/1.1-2    │ ← Application Layer
├─────────────────┤
│      TCP        │ ← Transport Layer
├─────────────────┤
│    TLS 1.3      │ ← Security Layer (Optional)
├─────────────────┤
│   IPv6/IPv4     │ ← Network Layer
└─────────────────┘
```

---

## 🏗️ Architecture

### Core Components

```
src/
├── main.rs           # CLI entry point and command handling
├── server.rs         # Core HTTP server implementation
├── config.rs         # TOML configuration parser and validation
├── tls.rs            # TLS certificate management
├── router.rs         # Request routing with pattern matching
├── proxy.rs          # Reverse proxy with load balancing
├── static_server.rs  # Static file serving with compression
├── admin.rs          # Web-based admin dashboard
├── metrics.rs        # Statistics collection and reporting
├── rate_limiter.rs   # Rate limiting (placeholder)
└── dns.rs            # DNS utilities
```

### System Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Client        │    │     Wraith      │    │   Upstream      │
│   Requests      │───▶│    Proxy        │───▶│   Servers       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │  Admin Dashboard│
                       │  & Metrics      │
                       └─────────────────┘
```

---

## 🔧 Core Features

### 1. HTTP Server (`server.rs`)

High-performance HTTP server built on Tokio and Hyper:

```rust
// Core server features:
- HTTP/1.1 and HTTP/2 support
- TLS termination with Rustls
- Graceful shutdown handling
- Request/response processing
- Admin API integration
```

### 2. TOML Configuration Parser (`config.rs`)

Declarative configuration with validation:

```toml
[server]
bind = "0.0.0.0:8080"
tls_bind = "0.0.0.0:8443"

[proxy]
enabled = true

[[proxy.routes]]
path = "/api/"
upstream = "backend"

[[proxy.upstreams]]
name = "backend"
servers = ["127.0.0.1:3000", "127.0.0.1:3001"]
load_balancing = "round_robin"
health_check = { enabled = true, interval = 30, timeout = 5 }
```

### 3. Smart Routing System (`router.rs`)

Advanced routing with multiple matching criteria:

```rust
// Routing features:
- Host-based routing
- Path prefix matching
- Header-based routing
- Configurable route priority
- Fallback handling
```

### 4. Reverse Proxy with Load Balancing (`proxy.rs`)

Full-featured reverse proxy implementation:

**Load Balancing Algorithms:**
- **Round Robin**: Even distribution across upstreams
- **Least Connections**: Route to least busy server
- **Random**: Random server selection
- **Weighted**: Weighted distribution based on server capacity
- **IP Hash**: Consistent routing based on client IP

**Health Checking:**
```rust
// Health check features:
- Configurable intervals and timeouts
- HTTP-based health checks
- Automatic failover
- Server recovery detection
- Real-time status updates
```

### 5. TLS Certificate Management (`tls.rs`)

Modern TLS implementation:

```rust
// TLS features:
- TLS 1.3 with Rustls
- Custom certificate loading
- SNI support
- Secure cipher suites
- Certificate validation
```

### 6. Static File Server (`static_server.rs`)

Advanced static file serving:

```rust
// Static server features:
- Gzip compression
- ETag generation
- Cache headers
- Range request support
- MIME type detection
- Security headers
```

### 7. Admin Dashboard (`admin.rs`)

Web-based administration interface:

```rust
// Admin features:
- Real-time metrics display
- Server control (reload, stop)
- Configuration viewing
- Health status monitoring
- Request statistics
```

---

## ⚙️ Configuration

### Main Configuration File (`wraith.toml`)

```toml
[server]
bind = "0.0.0.0:8080"
tls_bind = "0.0.0.0:8443"
worker_threads = 4

[tls]
cert_file = "certs/server.crt"
key_file = "certs/server.key"

[static]
enabled = true
root = "./public"
index_files = ["index.html", "index.htm"]
compression = true

[proxy]
enabled = true
timeout = 30

[[proxy.routes]]
host = "api.example.com"
path = "/v1/"
upstream = "api_backend"

[[proxy.upstreams]]
name = "api_backend"
servers = ["10.0.1.10:8080", "10.0.1.11:8080"]
load_balancing = "least_connections"

[proxy.upstreams.health_check]
enabled = true
interval = 30
timeout = 5
path = "/health"

[admin]
enabled = true
bind = "127.0.0.1:8090"

[logging]
level = "info"
format = "json"
```

### Environment Variables

```bash
WRAITH_CONFIG_FILE=/etc/wraith/wraith.toml
WRAITH_LOG_LEVEL=info
WRAITH_BIND_ADDRESS=0.0.0.0:8080
RUST_LOG=wraith=debug
```

---

## 🔒 Security Features

### Transport Security
- **TLS 1.3**: Modern cryptographic protocols
- **Perfect Forward Secrecy**: Session key isolation
- **Strong Cipher Suites**: Secure algorithm selection

### Application Security
- **Memory Safety**: Rust's ownership system prevents common vulnerabilities
- **Input Validation**: Comprehensive request validation
- **Security Headers**: Configurable HTTP security headers
- **Rate Limiting**: Protection against abuse (extensible)

### Operational Security
- **Graceful Degradation**: Healthy failover behavior
- **Resource Limits**: Protection against resource exhaustion
- **Audit Logging**: Comprehensive request/response logging

---

## 🚀 Performance Features

### Async Architecture
- **Tokio Runtime**: High-performance async I/O
- **Zero-Copy Operations**: Minimal memory allocation
- **Connection Pooling**: Efficient upstream connections

### Load Balancing
- **Multiple Algorithms**: Choose the best strategy for your workload
- **Health Checking**: Automatic failover and recovery
- **Real-time Metrics**: Monitor performance and health

### Caching & Compression
- **Static File Caching**: ETag and cache header support
- **Gzip Compression**: Automatic content compression
- **Memory Efficiency**: Rust's zero-cost abstractions

---

## 📊 Monitoring

### Metrics Collection

The metrics system provides comprehensive insights:

```rust
// Available metrics:
- Request count and rate
- Response times and latencies
- Error rates and status codes
- Upstream health status
- Connection statistics
- Memory and CPU usage
```

### Admin Dashboard

Access the web dashboard at `http://localhost:8090/admin/` for:

- **Real-time Metrics**: Live request and performance data
- **Server Status**: Current configuration and health
- **Upstream Monitoring**: Backend server health and statistics
- **System Controls**: Configuration reload, graceful shutdown

### Health Endpoints

```bash
# Server health
GET /admin/health

# Detailed metrics
GET /admin/metrics

# Configuration status
GET /admin/config
```

---

## 🚀 Deployment

### Building

```bash
# Development build
cargo build

# Optimized release build
cargo build --release

# With specific features
cargo build --release --features="admin,metrics"
```

### Running

```bash
# Start server
./target/release/wraith serve -c wraith.toml

# Development mode
cargo run -- serve --dev

# Test configuration
./target/release/wraith test -c wraith.toml
```

### Docker Deployment

```dockerfile
FROM rust:1.75 as builder
WORKDIR /app
COPY . .
RUN cargo build --release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/wraith /usr/local/bin/
COPY wraith.toml /etc/wraith/
EXPOSE 8080 8443
CMD ["wraith", "serve", "-c", "/etc/wraith/wraith.toml"]
```

### Systemd Service

```ini
[Unit]
Description=Wraith HTTP Proxy
After=network.target

[Service]
Type=simple
User=wraith
ExecStart=/usr/local/bin/wraith serve -c /etc/wraith/wraith.toml
ExecReload=/usr/local/bin/wraith reload
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

---

## 🔧 Development

### Building from Source

```bash
# Clone repository
git clone https://github.com/ghostkellz/wraith.git
cd wraith

# Build and test
cargo build
cargo test
cargo clippy

# Run development server
cargo run -- serve --dev
```

### Testing

```bash
# Unit tests
cargo test

# Integration tests
cargo test --test integration

# Benchmarks
cargo bench
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Run `cargo test` and `cargo clippy`
6. Submit a pull request

---

**Built with ❤️ using Rust, Tokio, Hyper, and Axum**