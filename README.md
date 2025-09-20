
<div align="center">
  <img src="assets/icons/wraith-proxy.png" alt="Wraith Logo" width="200"/>
</div>

## 📌 Wraith
A modern, blazing-fast, secure reverse proxy and static site server built with Rust. Designed for high-performance HTTP/1.1 and HTTP/2 traffic with advanced load balancing, health checking, and an intuitive admin interface.

---

## 🌐 Key Protocol Stack

* **HTTP/1.1 & HTTP/2**: Full protocol support
* **TLS 1.3**: Built-in, hardened, minimal config
* **IPv4/IPv6**: Dual-stack support
* **WebSocket**: Proxy support with upgrade handling

---

## 🔧 Core Features

* ⚡ **Zero-downtime Hot Reloads** via admin API
* ⚙️ **Declarative TOML Configuration**
* 🧠 **Smart Routing Layer** with Host/Path/Header matching
* 🔒 **Built-in Rate Limiting and Health Checking**
* 📦 **Edge-Ready**: Statically compiled Rust binary
* 🔁 **Advanced Load Balancing** (Round Robin, Least Connections, Random, Weighted, IP Hash)
* 📁 **Static File Server** with compression and caching
* 🛰 **Web-based Admin Dashboard** with real-time metrics
* 📊 **Comprehensive Metrics** and monitoring

---

## 🚀 Features

* **High Performance**: Built with Rust's async ecosystem (Tokio, Hyper, Axum)
* **Production Ready**: Memory-safe, zero-cost abstractions
* **Easy Deployment**: Single binary with minimal dependencies
* **Extensible**: Modular architecture for future enhancements

---

## 📦 CLI Commands

```bash
# Start the server
wraith serve -c wraith.toml

# Test configuration
wraith test -c wraith.toml

# Reload configuration (hot reload)
wraith reload

# Stop the server gracefully
wraith stop

# Check server status
wraith status

# Show version
wraith version
```

---

## 🧪 Development

* Built with Rust 2024 edition
* Uses Tokio for async runtime
* TLS certificates stored in `~/.wraith/certs/` or `/etc/wraith/certs/`
* Optimized release builds with LTO and strip

---
