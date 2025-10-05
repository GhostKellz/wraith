# Wraith Architecture

## Overview

Wraith is a next-generation web server and reverse proxy built in Zig, designed to be a modern alternative to nginx with support for HTTP/3, QUIC, TLS 1.3, and zero-trust security features.

## Core Components

### 1. HTTP Server (`src/server/http_server.zig`)

The main HTTP server component that:
- Listens on configured addresses (HTTP and HTTPS)
- Accepts incoming connections
- Handles graceful shutdown via SIGTERM/SIGINT
- Supports hot reload via SIGHUP
- Integrates with signal handlers and proxy forwarder

**Key Dependencies:**
- `zsync` - Async runtime for handling concurrent connections
- `zhttp` - HTTP/1.1 and HTTP/2 protocol implementation
- `signals.zig` - Signal handling for process lifecycle

### 2. Signal Handlers (`src/server/signals.zig`)

POSIX signal handling for process control:
- **SIGTERM/SIGINT** → Graceful shutdown (drains connections, saves state)
- **SIGHUP** → Hot reload (reloads config without dropping connections)

Uses atomic flags for thread-safe signal coordination between signal handlers and the main event loop.

### 3. TLS/QUIC Server (`src/server/tls.zig`)

Protocol upgrade layer providing:
- **TLS 1.3** support via `zcrypto`
  - Certificate loading and validation
  - Secure handshake negotiation
- **QUIC/HTTP3** support via `zquic`
  - Post-quantum cryptography (PQC) algorithms
  - 0-RTT connection establishment
  - BBR congestion control

### 4. Proxy Forwarder (`src/proxy/forwarder.zig`)

Request forwarding engine that:
- Establishes upstream connections
- Copies headers and body between client and upstream
- Handles connection pooling and keepalive
- Supports various load balancing algorithms

### 5. Configuration (`src/config/config.zig`)

TOML-based configuration system using `flare`:
- Server settings (listen addresses, worker threads)
- TLS certificates and cipher suites
- Upstream definitions with health checks
- Routing rules with pattern matching
- Logging and observability settings

### 6. CLI (`src/cli/commands.zig`)

Command-line interface using `flash`:
- `wraith serve` - Start the server
- `wraith test` - Test configuration validity
- `wraith reload` - Send SIGHUP to running process
- `wraith stop` - Send SIGTERM for graceful shutdown
- `wraith status` - Query server status
- `wraith version` - Display version info

## Architecture Diagram

```
┌─────────────────────────────────────────────────┐
│                  CLI (flash)                    │
│  serve │ test │ reload │ stop │ status │ version│
└─────────────────────┬───────────────────────────┘
                      │
                      ▼
          ┌───────────────────────┐
          │  Config (flare/TOML)  │
          │   - Server settings   │
          │   - Upstreams         │
          │   - Routes            │
          │   - TLS certs         │
          └───────────┬───────────┘
                      │
                      ▼
        ┌─────────────────────────────┐
        │   Signal Handlers (POSIX)   │
        │  SIGTERM │ SIGINT │ SIGHUP  │
        └─────────────┬───────────────┘
                      │
                      ▼
          ┌───────────────────────┐
          │   HTTP Server (zhttp) │
          │  - Accept connections │
          │  - Route requests     │
          │  - Handle protocols   │
          └───────┬───────────────┘
                  │
         ┌────────┴────────┐
         ▼                 ▼
┌─────────────────┐  ┌──────────────────┐
│  TLS/QUIC Layer │  │ Proxy Forwarder  │
│   (zcrypto)     │  │  - Load balance  │
│   - TLS 1.3     │  │  - Health checks │
│   - HTTP/3      │  │  - Connection    │
│   - QUIC (PQC)  │  │    pooling       │
└─────────────────┘  └────────┬─────────┘
                              │
                              ▼
                      ┌───────────────┐
                      │   Upstreams   │
                      │  (backends)   │
                      └───────────────┘
```

## Protocol Support

### HTTP/1.1 (Current)
- Request/response parsing via `zhttp`
- Connection keepalive
- Chunked transfer encoding
- Header forwarding

### HTTP/2 (Planned)
- Binary framing via `zhttp`
- Server push
- Stream multiplexing
- Header compression (HPACK)

### HTTP/3 + QUIC (Foundation Laid)
- UDP transport via `zquic`
- Post-quantum cryptography
- 0-RTT resumption
- Improved congestion control (BBR)
- Stream prioritization

## Load Balancing

Supported algorithms:
- **Round Robin** - Distribute requests evenly
- **Least Connections** - Send to server with fewest active connections
- **Weighted** - Distribute based on server capacity weights
- **IP Hash** - Consistent hashing for session affinity
- **Random** - Random selection with health awareness

## Observability

### Logging (`zlog`)
- Structured JSON logging
- Multiple log levels (debug, info, warn, error)
- SQL-queryable logs via `zqlite`
  - Embedded SQLite database
  - Real-time log analysis with SQL
  - Example: `SELECT * FROM access_log WHERE status >= 500`

### Metrics
- Request latency histograms
- Active connection counts
- Upstream health status
- Error rates by route/upstream
- TLS handshake performance

## Zero-Trust Security

### Integrations (Planned)
- **CrowdSec** - Collaborative threat intelligence
- **Wazuh** - SIEM and intrusion detection
- **Tailscale** - Zero-trust network access
- **mTLS** - Mutual TLS authentication

## Technology Stack

### Core Libraries
- **zsync** - Async runtime (RC quality)
- **zhttp** - HTTP/1.1 & HTTP/2 (alpha)
- **zcrypto** - TLS 1.3 cryptography
- **zquic** - QUIC + post-quantum crypto
- **flash** - CLI framework
- **flare** - Configuration management
- **zlog** - Structured logging
- **zqlite** - SQL-queryable logs

### Performance & Utilities
- **zpack** - Compression (gzip/brotli)
- **zregex** - Route pattern matching
- **ztime** - HTTP date/time headers
- **phantom** - TUI for `wraith top`

## Development Workflow

1. **Configuration** - Edit `wraith.toml` with upstreams and routes
2. **Test Config** - Run `wraith test -c wraith.toml` to validate
3. **Start Server** - Run `wraith serve -c wraith.toml`
4. **Monitor** - Use `wraith status` or logs for observability
5. **Hot Reload** - Send SIGHUP: `wraith reload` or `kill -HUP <pid>`
6. **Graceful Stop** - Send SIGTERM: `wraith stop` or `kill -TERM <pid>`

## Performance Characteristics

- **Single binary** - No runtime dependencies
- **Low memory footprint** - Zig's memory efficiency
- **Zero-copy forwarding** - Minimize data copying in proxy path
- **Connection pooling** - Reuse upstream connections
- **Async I/O** - Non-blocking event loop via `zsync`

## Future Enhancements

- gRPC proxy support via `zrpc`
- SSH tunnel management via `zssh`
- Web3 integrations (ENS, IPFS, Ethereum RPC)
- Advanced rate limiting and DDoS protection
- Custom Lua/WASM plugins for request transformation
