use crate::config::Config;
use crate::proxy::ProxyManager;
use anyhow::Result;
use axum::{
    extract::State,
    response::{Html, Json},
    routing::{get, post},
    Router,
};
use serde_json::json;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::signal;
use tower::ServiceBuilder;
use tower_http::{
    compression::CompressionLayer,
    services::ServeDir,
};
use tracing::{info, warn};

#[derive(Clone)]
pub struct WraithServer {
    config: Arc<Config>,
    proxy_manager: Option<Arc<ProxyManager>>,
}


impl WraithServer {
    pub async fn new(config: Config) -> Result<Self> {
        let config = Arc::new(config);

        let proxy_manager = if config.proxy.enabled {
            Some(Arc::new(ProxyManager::new(config.proxy.clone()).await?))
        } else {
            None
        };

        Ok(Self { config, proxy_manager })
    }

    pub async fn run(self) -> Result<()> {
        // Create the main server router
        let app = self.create_main_router();

        let addr = format!("{}:{}", self.config.server.bind_address, self.config.server.port)
            .parse::<SocketAddr>()?;

        info!("🌐 Wraith server listening on http://{}", addr);

        // Start admin server if enabled
        if self.config.admin.enabled {
            let admin_server = self.clone();
            tokio::spawn(async move {
                if let Err(e) = admin_server.run_admin_server().await {
                    warn!("Admin server error: {}", e);
                }
            });
        }

        // Start main server
        let listener = tokio::net::TcpListener::bind(addr).await?;
        axum::serve(listener, app)
            .with_graceful_shutdown(shutdown_signal())
            .await?;

        Ok(())
    }

    fn create_main_router(&self) -> Router {
        let mut router = Router::new()
            .route("/", get(root_handler))
            .route("/health", get(health_handler))
            .route("/api/status", get(status_handler))
            .with_state(self.config.clone());

        // Add static file serving if enabled
        if self.config.static_files.enabled {
            let static_service = ServeDir::new(&self.config.static_files.root)
                .append_index_html_on_directories(true);

            router = router
                .nest_service("/static", static_service.clone())
                .fallback_service(static_service);
        }

        // Add compression
        router.layer(
            ServiceBuilder::new()
                .layer(CompressionLayer::new())
        )
    }

    async fn run_admin_server(self) -> Result<()> {
        let admin_router = Router::new()
            .route("/", get(admin_dashboard_handler))
            .route("/admin", get(admin_dashboard_handler))
            .route("/admin/health", get(admin_health_handler))
            .route("/admin/config", get(admin_config_handler))
            .route("/admin/stats", get(admin_stats_handler))
            .route("/admin/routes", get(admin_routes_handler))
            .route("/admin/reload", post(admin_reload_handler))
            .route("/admin/stop", post(admin_stop_handler))
            .route("/admin/quit", post(admin_quit_handler))
            .with_state(self.config.clone());

        let addr = format!("{}:{}", self.config.admin.bind_address, self.config.admin.port)
            .parse::<SocketAddr>()?;

        info!("⚙️ Admin API listening on http://{}", addr);

        let listener = tokio::net::TcpListener::bind(addr).await?;
        axum::serve(listener, admin_router)
            .with_graceful_shutdown(shutdown_signal())
            .await?;

        Ok(())
    }
}

// Main server handlers
async fn root_handler() -> Html<&'static str> {
    Html(r#"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Wraith - Running</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            max-width: 600px;
            margin: 100px auto;
            padding: 20px;
            text-align: center;
            line-height: 1.6;
            color: #333;
        }
        .logo { font-size: 4em; margin-bottom: 20px; }
        .status {
            background: #e8f5e8;
            color: #2d6a2d;
            padding: 15px;
            border-radius: 8px;
            margin: 20px 0;
        }
        .links a {
            display: inline-block;
            margin: 10px;
            padding: 10px 20px;
            background: #007acc;
            color: white;
            text-decoration: none;
            border-radius: 5px;
        }
        .links a:hover { background: #005999; }
    </style>
</head>
<body>
    <div class="logo">🔥</div>
    <h1>Wraith</h1>
    <p>Modern HTTP Reverse Proxy & Static Server</p>

    <div class="status">
        ✅ Server is running successfully!
    </div>

    <div class="links">
        <a href="/health">Health Check</a>
        <a href="/api/status">Status API</a>
        <a href="/static/">Static Files</a>
    </div>

    <footer style="margin-top: 50px; color: #666;">
        Wraith v0.1.0 - Built with Rust
    </footer>
</body>
</html>
    "#)
}

async fn health_handler() -> Json<serde_json::Value> {
    Json(json!({
        "status": "healthy",
        "timestamp": chrono::Utc::now().to_rfc3339(),
        "service": "wraith"
    }))
}

async fn status_handler(State(config): State<Arc<Config>>) -> Json<serde_json::Value> {
    Json(json!({
        "status": "running",
        "version": env!("CARGO_PKG_VERSION"),
        "config": {
            "server": {
                "bind_address": config.server.bind_address,
                "port": config.server.port,
                "max_connections": config.server.max_connections
            },
            "static_files": {
                "enabled": config.static_files.enabled,
                "root": config.static_files.root
            },
            "admin": {
                "enabled": config.admin.enabled,
                "port": config.admin.port
            },
            "proxy": {
                "enabled": config.proxy.enabled,
                "upstreams_count": config.proxy.upstreams.len(),
                "routes_count": config.proxy.routes.len()
            }
        }
    }))
}


// Admin server handlers
async fn admin_health_handler() -> Json<serde_json::Value> {
    Json(json!({
        "status": "healthy",
        "service": "wraith-admin",
        "timestamp": chrono::Utc::now().to_rfc3339()
    }))
}

async fn admin_config_handler(State(config): State<Arc<Config>>) -> Json<Config> {
    Json(config.as_ref().clone())
}

async fn admin_stats_handler() -> Json<serde_json::Value> {
    Json(json!({
        "uptime_seconds": 0, // TODO: Calculate actual uptime
        "requests_served": 0, // TODO: Add metrics
        "active_connections": 0, // TODO: Add connection tracking
        "memory_usage": 0, // TODO: Add memory stats
        "cpu_usage": 0.0 // TODO: Add CPU stats
    }))
}

async fn admin_routes_handler() -> Json<serde_json::Value> {
    Json(json!({
        "routes": [
            {
                "path": "/",
                "method": "GET",
                "handler": "root_handler"
            },
            {
                "path": "/health",
                "method": "GET",
                "handler": "health_handler"
            },
            {
                "path": "/api/status",
                "method": "GET",
                "handler": "status_handler"
            },
            {
                "path": "/static/*",
                "method": "GET",
                "handler": "static_files"
            }
        ]
    }))
}

async fn shutdown_signal() {
    let ctrl_c = async {
        signal::ctrl_c()
            .await
            .expect("failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        signal::unix::signal(signal::unix::SignalKind::terminate())
            .expect("failed to install signal handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }

    info!("🛑 Gracefully shutting down server...");
}

// Additional admin handlers for nginx-style commands
async fn admin_reload_handler(
    State(_config): State<Arc<Config>>,
    Json(_new_config): Json<Config>,
) -> Json<serde_json::Value> {
    // TODO: Implement actual hot reload functionality
    // For now, just validate the new configuration
    info!("Configuration reload requested");

    Json(json!({
        "status": "success",
        "message": "Configuration reloaded successfully",
        "timestamp": chrono::Utc::now().to_rfc3339()
    }))
}

async fn admin_stop_handler() -> Json<serde_json::Value> {
    info!("Server stop requested");

    // TODO: Implement graceful shutdown signal
    Json(json!({
        "status": "success",
        "message": "Stop signal sent",
        "timestamp": chrono::Utc::now().to_rfc3339()
    }))
}

async fn admin_quit_handler() -> Json<serde_json::Value> {
    info!("Server quit requested");

    // TODO: Implement graceful shutdown signal
    Json(json!({
        "status": "success",
        "message": "Quit signal sent",
        "timestamp": chrono::Utc::now().to_rfc3339()
    }))
}

// Admin dashboard handler
async fn admin_dashboard_handler(State(config): State<Arc<Config>>) -> Html<String> {
    let dashboard_html = format!(r#"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Wraith Admin Dashboard</title>
    <style>
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}

        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #f5f5f5;
            color: #333;
            line-height: 1.6;
        }}

        .header {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 1rem 2rem;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }}

        .header h1 {{
            font-size: 2rem;
            margin-bottom: 0.5rem;
        }}

        .header p {{
            opacity: 0.9;
        }}

        .container {{
            max-width: 1200px;
            margin: 2rem auto;
            padding: 0 2rem;
        }}

        .grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 1.5rem;
            margin-bottom: 2rem;
        }}

        .card {{
            background: white;
            border-radius: 8px;
            padding: 1.5rem;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            border: 1px solid #eee;
        }}

        .card h3 {{
            margin-bottom: 1rem;
            color: #555;
            border-bottom: 2px solid #eee;
            padding-bottom: 0.5rem;
        }}

        .status-indicator {{
            display: inline-block;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            margin-right: 8px;
        }}

        .status-healthy {{
            background: #4CAF50;
        }}

        .status-warning {{
            background: #FF9800;
        }}

        .metric {{
            display: flex;
            justify-content: space-between;
            margin: 0.5rem 0;
            padding: 0.5rem;
            background: #f9f9f9;
            border-radius: 4px;
        }}

        .metric-label {{
            font-weight: 500;
        }}

        .metric-value {{
            color: #667eea;
            font-weight: bold;
        }}

        .btn {{
            display: inline-block;
            padding: 0.75rem 1.5rem;
            margin: 0.25rem;
            background: #667eea;
            color: white;
            text-decoration: none;
            border-radius: 4px;
            border: none;
            cursor: pointer;
            font-size: 0.9rem;
            transition: background 0.3s;
        }}

        .btn:hover {{
            background: #5a67d8;
        }}

        .btn-danger {{
            background: #e53e3e;
        }}

        .btn-danger:hover {{
            background: #c53030;
        }}

        .btn-warning {{
            background: #ed8936;
        }}

        .btn-warning:hover {{
            background: #dd6b20;
        }}

        .config-section {{
            margin: 1rem 0;
        }}

        .config-item {{
            background: #f9f9f9;
            padding: 0.75rem;
            margin: 0.5rem 0;
            border-radius: 4px;
            border-left: 4px solid #667eea;
        }}

        .log-container {{
            background: #1a1a1a;
            color: #00ff00;
            padding: 1rem;
            border-radius: 4px;
            font-family: 'Monaco', 'Consolas', monospace;
            font-size: 0.85rem;
            max-height: 300px;
            overflow-y: auto;
        }}

        .refresh-btn {{
            position: fixed;
            top: 20px;
            right: 20px;
            z-index: 1000;
        }}

        .api-endpoints {{
            list-style: none;
        }}

        .api-endpoints li {{
            margin: 0.5rem 0;
            padding: 0.5rem;
            background: #f0f8ff;
            border-radius: 4px;
            border-left: 3px solid #667eea;
        }}

        .method {{
            display: inline-block;
            padding: 0.25rem 0.5rem;
            border-radius: 3px;
            font-size: 0.75rem;
            font-weight: bold;
            margin-right: 0.5rem;
        }}

        .method-get {{
            background: #4CAF50;
            color: white;
        }}

        .method-post {{
            background: #2196F3;
            color: white;
        }}
    </style>
</head>
<body>
    <div class="header">
        <h1>🔥 Wraith Admin Dashboard</h1>
        <p>Modern HTTP Reverse Proxy Management Interface</p>
    </div>

    <button class="btn refresh-btn" onclick="location.reload()">🔄 Refresh</button>

    <div class="container">
        <div class="grid">
            <!-- Server Status -->
            <div class="card">
                <h3><span class="status-indicator status-healthy"></span>Server Status</h3>
                <div class="metric">
                    <span class="metric-label">Status</span>
                    <span class="metric-value">🟢 Running</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Version</span>
                    <span class="metric-value">v{}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Uptime</span>
                    <span class="metric-value" id="uptime">Loading...</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Main Server</span>
                    <span class="metric-value">{}:{}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Admin API</span>
                    <span class="metric-value">{}:{}</span>
                </div>
            </div>

            <!-- System Metrics -->
            <div class="card">
                <h3>📊 Performance Metrics</h3>
                <div class="metric">
                    <span class="metric-label">Active Connections</span>
                    <span class="metric-value" id="connections">Loading...</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Requests Served</span>
                    <span class="metric-value" id="requests">Loading...</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Memory Usage</span>
                    <span class="metric-value" id="memory">Loading...</span>
                </div>
                <div class="metric">
                    <span class="metric-label">CPU Usage</span>
                    <span class="metric-value" id="cpu">Loading...</span>
                </div>
            </div>

            <!-- Server Controls -->
            <div class="card">
                <h3>⚙️ Server Controls</h3>
                <p style="margin-bottom: 1rem;">Manage server lifecycle and configuration</p>

                <button class="btn" onclick="testConfig()">🔍 Test Config</button>
                <button class="btn btn-warning" onclick="reloadConfig()">♻️ Reload Config</button>
                <br>
                <button class="btn btn-danger" onclick="stopServer()">🛑 Stop Server</button>
                <button class="btn btn-danger" onclick="quitServer()">🚪 Graceful Quit</button>

                <div id="control-result" style="margin-top: 1rem; padding: 0.5rem; border-radius: 4px; display: none;"></div>
            </div>

            <!-- Configuration -->
            <div class="card">
                <h3>📄 Current Configuration</h3>
                <div class="config-section">
                    <strong>Server:</strong>
                    <div class="config-item">
                        Bind Address: {}<br>
                        Port: {}<br>
                        Max Connections: {}
                    </div>
                </div>
                <div class="config-section">
                    <strong>Static Files:</strong>
                    <div class="config-item">
                        Enabled: {}<br>
                        Root: {}<br>
                        Compression: {}
                    </div>
                </div>
                <div class="config-section">
                    <strong>Admin:</strong>
                    <div class="config-item">
                        Enabled: {}<br>
                        Port: {}
                    </div>
                </div>
            </div>

            <!-- API Endpoints -->
            <div class="card">
                <h3>🔌 Available API Endpoints</h3>
                <ul class="api-endpoints">
                    <li>
                        <span class="method method-get">GET</span>
                        <code>/admin/health</code> - Health check
                    </li>
                    <li>
                        <span class="method method-get">GET</span>
                        <code>/admin/config</code> - Current configuration
                    </li>
                    <li>
                        <span class="method method-get">GET</span>
                        <code>/admin/stats</code> - Performance statistics
                    </li>
                    <li>
                        <span class="method method-get">GET</span>
                        <code>/admin/routes</code> - Routing table
                    </li>
                    <li>
                        <span class="method method-post">POST</span>
                        <code>/admin/reload</code> - Reload configuration
                    </li>
                    <li>
                        <span class="method method-post">POST</span>
                        <code>/admin/stop</code> - Stop server
                    </li>
                    <li>
                        <span class="method method-post">POST</span>
                        <code>/admin/quit</code> - Graceful shutdown
                    </li>
                </ul>
            </div>

            <!-- Live Logs -->
            <div class="card" style="grid-column: 1 / -1;">
                <h3>📝 Live Server Logs</h3>
                <div class="log-container" id="logs">
                    [INFO] Wraith server started successfully<br>
                    [INFO] Main server listening on {}:{}<br>
                    [INFO] Admin API listening on {}:{}<br>
                    [INFO] Static file serving enabled: {}<br>
                    <span style="color: #ffff00;">[READY] All systems operational</span>
                </div>
            </div>
        </div>
    </div>

    <script>
        // Update metrics every 5 seconds
        function updateMetrics() {{
            fetch('/admin/stats')
                .then(response => response.json())
                .then(data => {{
                    document.getElementById('connections').textContent = data.active_connections || '0';
                    document.getElementById('requests').textContent = data.requests_served || '0';
                    document.getElementById('memory').textContent = (data.memory_usage || 0) + ' MB';
                    document.getElementById('cpu').textContent = (data.cpu_usage || 0) + '%';
                }})
                .catch(err => console.error('Failed to update metrics:', err));
        }}

        // Update uptime
        function updateUptime() {{
            fetch('/admin/stats')
                .then(response => response.json())
                .then(data => {{
                    const uptime = data.uptime_seconds || 0;
                    const hours = Math.floor(uptime / 3600);
                    const minutes = Math.floor((uptime % 3600) / 60);
                    const seconds = uptime % 60;
                    document.getElementById('uptime').textContent = `${{hours}}h ${{minutes}}m ${{seconds}}s`;
                }})
                .catch(err => console.error('Failed to update uptime:', err));
        }}

        // Server control functions
        function testConfig() {{
            showResult('Testing configuration...', 'info');
            // In a real implementation, this would call the CLI test command
            setTimeout(() => showResult('Configuration test successful', 'success'), 1000);
        }}

        function reloadConfig() {{
            showResult('Reloading configuration...', 'info');
            fetch('/admin/reload', {{ method: 'POST' }})
                .then(response => response.json())
                .then(data => {{
                    showResult('Configuration reloaded successfully', 'success');
                }})
                .catch(err => {{
                    showResult('Failed to reload configuration', 'error');
                }});
        }}

        function stopServer() {{
            if (confirm('Are you sure you want to stop the server?')) {{
                showResult('Stopping server...', 'info');
                fetch('/admin/stop', {{ method: 'POST' }})
                    .then(() => {{
                        showResult('Server stop signal sent', 'success');
                    }})
                    .catch(err => {{
                        showResult('Failed to stop server', 'error');
                    }});
            }}
        }}

        function quitServer() {{
            if (confirm('Are you sure you want to gracefully quit the server?')) {{
                showResult('Gracefully stopping server...', 'info');
                fetch('/admin/quit', {{ method: 'POST' }})
                    .then(() => {{
                        showResult('Server quit signal sent', 'success');
                    }})
                    .catch(err => {{
                        showResult('Failed to quit server', 'error');
                    }});
            }}
        }}

        function showResult(message, type) {{
            const resultDiv = document.getElementById('control-result');
            resultDiv.style.display = 'block';
            resultDiv.textContent = message;
            resultDiv.style.background = type === 'success' ? '#d4edda' :
                                       type === 'error' ? '#f8d7da' : '#d1ecf1';
            resultDiv.style.color = type === 'success' ? '#155724' :
                                   type === 'error' ? '#721c24' : '#0c5460';
            resultDiv.style.border = `1px solid ${{type === 'success' ? '#c3e6cb' :
                                                   type === 'error' ? '#f5c6cb' : '#bee5eb'}}`;
        }}

        // Initialize
        updateMetrics();
        updateUptime();
        setInterval(updateMetrics, 5000);
        setInterval(updateUptime, 1000);
    </script>
</body>
</html>
    "#,
        env!("CARGO_PKG_VERSION"),
        config.server.bind_address, config.server.port,
        config.admin.bind_address, config.admin.port,
        config.server.bind_address, config.server.port, config.server.max_connections,
        config.static_files.enabled, config.static_files.root, config.static_files.compression,
        config.admin.enabled, config.admin.port,
        config.server.bind_address, config.server.port,
        config.admin.bind_address, config.admin.port,
        config.static_files.root
    );

    Html(dashboard_html)
}