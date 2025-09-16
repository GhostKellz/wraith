use crate::{config::Config, proxy::ProxyManager, router::Router};
use anyhow::Result;
use arc_swap::ArcSwap;
use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::Json,
    routing::{get, post, delete},
    Router as AxumRouter,
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use tower::ServiceBuilder;
use tower_http::cors::CorsLayer;
use tracing::{info, warn};

#[derive(Clone)]
pub struct AdminServer {
    config: Arc<ArcSwap<Config>>,
    router: Arc<Router>,
    proxy_manager: Arc<ProxyManager>,
}

#[derive(Serialize, Deserialize)]
struct ServerStatus {
    status: String,
    uptime: u64,
    version: String,
    config_version: String,
}

#[derive(Serialize, Deserialize)]
struct ServerStats {
    proxy: serde_json::Value,
    router: serde_json::Value,
    static_files: serde_json::Value,
    rate_limiter: serde_json::Value,
}

#[derive(Serialize, Deserialize)]
struct ReloadRequest {
    config: Option<Config>,
}

#[derive(Serialize, Deserialize)]
struct ApiResponse<T> {
    success: bool,
    data: Option<T>,
    message: Option<String>,
}

impl AdminServer {
    pub fn new(
        config: Arc<ArcSwap<Config>>,
        router: Arc<Router>,
        proxy_manager: Arc<ProxyManager>,
    ) -> Self {
        Self {
            config,
            router,
            proxy_manager,
        }
    }

    pub async fn run(self) -> Result<()> {
        let bind_addr = format!(
            "{}:{}",
            self.config.load().admin.bind_address,
            self.config.load().admin.port
        );

        let addr: SocketAddr = bind_addr.parse()?;

        let app = self.create_routes();

        info!("Admin server listening on {}", addr);

        let listener = tokio::net::TcpListener::bind(addr).await?;
        axum::serve(listener, app).await?;

        Ok(())
    }

    fn create_routes(self) -> AxumRouter {
        AxumRouter::new()
            // Health and status endpoints
            .route("/health", get(health_check))
            .route("/status", get(get_status))
            .route("/stats", get(get_stats))

            // Configuration management
            .route("/admin/config", get(get_config))
            .route("/admin/reload", post(reload_config))

            // Route management
            .route("/admin/routes", get(list_routes))
            .route("/admin/routes", post(add_route))
            .route("/admin/routes/:id", delete(remove_route))

            // Upstream management
            .route("/admin/upstreams", get(list_upstreams))
            .route("/admin/upstreams/:name/health", get(get_upstream_health))

            // Rate limiting management
            .route("/admin/rate-limit/stats", get(get_rate_limit_stats))
            .route("/admin/rate-limit/unblock/:ip", post(unblock_ip))

            // Metrics (Prometheus format)
            .route("/metrics", get(get_metrics))

            // Certificate management
            .route("/admin/certs/info", get(get_cert_info))
            .route("/admin/certs/renew", post(renew_certificates))

            .layer(
                ServiceBuilder::new()
                    .layer(CorsLayer::permissive())
            )
            .with_state(self)
    }
}

// Handler functions
async fn health_check() -> Json<ApiResponse<HashMap<String, String>>> {
    let mut data = HashMap::new();
    data.insert("status".to_string(), "healthy".to_string());
    data.insert("timestamp".to_string(), chrono::Utc::now().to_rfc3339());

    Json(ApiResponse {
        success: true,
        data: Some(data),
        message: None,
    })
}

async fn get_status(
    State(admin): State<AdminServer>,
) -> Json<ApiResponse<ServerStatus>> {
    let uptime = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();

    let status = ServerStatus {
        status: "running".to_string(),
        uptime,
        version: env!("CARGO_PKG_VERSION").to_string(),
        config_version: "1.0".to_string(), // TODO: Add config versioning
    };

    Json(ApiResponse {
        success: true,
        data: Some(status),
        message: None,
    })
}

async fn get_stats(
    State(admin): State<AdminServer>,
) -> Json<ApiResponse<ServerStats>> {
    let proxy_stats = admin.proxy_manager.get_stats().await;

    // TODO: Get actual stats from other components
    let router_stats = serde_json::json!({
        "total_routes": admin.router.list_routes().len(),
    });

    let static_files_stats = serde_json::json!({
        "served_files": 0,
        "cache_size": 0,
    });

    let rate_limiter_stats = serde_json::json!({
        "active_limits": 0,
        "blocked_ips": 0,
    });

    let stats = ServerStats {
        proxy: proxy_stats.into(),
        router: router_stats,
        static_files: static_files_stats,
        rate_limiter: rate_limiter_stats,
    };

    Json(ApiResponse {
        success: true,
        data: Some(stats),
        message: None,
    })
}

async fn get_config(
    State(admin): State<AdminServer>,
) -> Json<ApiResponse<Config>> {
    let config = admin.config.load().clone();

    Json(ApiResponse {
        success: true,
        data: Some((**config).clone()),
        message: None,
    })
}

async fn reload_config(
    State(admin): State<AdminServer>,
    Json(request): Json<ReloadRequest>,
) -> Result<Json<ApiResponse<String>>, StatusCode> {
    if let Some(new_config) = request.config {
        // Validate config before applying
        // TODO: Add config validation logic

        // Update the config
        admin.config.store(Arc::new(new_config));

        info!("Configuration reloaded successfully");

        Ok(Json(ApiResponse {
            success: true,
            data: Some("Configuration reloaded".to_string()),
            message: None,
        }))
    } else {
        Ok(Json(ApiResponse {
            success: false,
            data: None,
            message: Some("No configuration provided".to_string()),
        }))
    }
}

async fn list_routes(
    State(admin): State<AdminServer>,
) -> Json<ApiResponse<Vec<crate::router::RouteInfo>>> {
    let routes = admin.router.list_routes();

    Json(ApiResponse {
        success: true,
        data: Some(routes),
        message: None,
    })
}

#[derive(Deserialize)]
struct AddRouteRequest {
    path: String,
    host: Option<String>,
    methods: Vec<String>,
    upstream: String,
    priority: Option<u32>,
}

async fn add_route(
    State(admin): State<AdminServer>,
    Json(request): Json<AddRouteRequest>,
) -> Result<Json<ApiResponse<String>>, StatusCode> {
    // TODO: Implement route addition
    // This would require making Router mutable or using interior mutability

    warn!("Route addition not yet implemented");

    Ok(Json(ApiResponse {
        success: false,
        data: None,
        message: Some("Route addition not yet implemented".to_string()),
    }))
}

async fn remove_route(
    State(admin): State<AdminServer>,
    Path(id): Path<String>,
) -> Result<Json<ApiResponse<String>>, StatusCode> {
    // TODO: Implement route removal
    warn!("Route removal not yet implemented for ID: {}", id);

    Ok(Json(ApiResponse {
        success: false,
        data: None,
        message: Some("Route removal not yet implemented".to_string()),
    }))
}

async fn list_upstreams(
    State(admin): State<AdminServer>,
) -> Json<ApiResponse<Vec<serde_json::Value>>> {
    let stats = admin.proxy_manager.get_stats().await;

    if let Some(upstreams) = stats.get("upstreams") {
        if let Some(upstream_array) = upstreams.as_array() {
            Json(ApiResponse {
                success: true,
                data: Some(upstream_array.clone()),
                message: None,
            })
        } else {
            Json(ApiResponse {
                success: false,
                data: None,
                message: Some("Invalid upstream data format".to_string()),
            })
        }
    } else {
        Json(ApiResponse {
            success: true,
            data: Some(vec![]),
            message: None,
        })
    }
}

async fn get_upstream_health(
    State(admin): State<AdminServer>,
    Path(name): Path<String>,
) -> Json<ApiResponse<serde_json::Value>> {
    let stats = admin.proxy_manager.get_stats().await;

    if let Some(upstreams) = stats.get("upstreams") {
        if let Some(upstream_array) = upstreams.as_array() {
            for upstream in upstream_array {
                if let Some(upstream_name) = upstream.get("name") {
                    if upstream_name.as_str() == Some(&name) {
                        return Json(ApiResponse {
                            success: true,
                            data: Some(upstream.clone()),
                            message: None,
                        });
                    }
                }
            }
        }
    }

    Json(ApiResponse {
        success: false,
        data: None,
        message: Some("Upstream not found".to_string()),
    })
}

async fn get_rate_limit_stats(
    State(admin): State<AdminServer>,
) -> Json<ApiResponse<serde_json::Value>> {
    // TODO: Get actual rate limit stats
    let stats = serde_json::json!({
        "total_requests": 0,
        "blocked_requests": 0,
        "active_limits": 0,
    });

    Json(ApiResponse {
        success: true,
        data: Some(stats),
        message: None,
    })
}

async fn unblock_ip(
    State(admin): State<AdminServer>,
    Path(ip): Path<String>,
) -> Result<Json<ApiResponse<String>>, StatusCode> {
    // TODO: Implement IP unblocking
    warn!("IP unblocking not yet implemented for: {}", ip);

    Ok(Json(ApiResponse {
        success: false,
        data: None,
        message: Some("IP unblocking not yet implemented".to_string()),
    }))
}

async fn get_metrics(
    State(admin): State<AdminServer>,
) -> Result<String, StatusCode> {
    // Generate Prometheus metrics
    let mut metrics = String::new();

    // Server metrics
    metrics.push_str("# HELP wraith_uptime_seconds Server uptime in seconds\n");
    metrics.push_str("# TYPE wraith_uptime_seconds counter\n");
    let uptime = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    metrics.push_str(&format!("wraith_uptime_seconds {}\n", uptime));

    // Proxy metrics
    let proxy_stats = admin.proxy_manager.get_stats().await;
    if let Some(total_requests) = proxy_stats.get("total_requests") {
        metrics.push_str("# HELP wraith_proxy_requests_total Total proxy requests\n");
        metrics.push_str("# TYPE wraith_proxy_requests_total counter\n");
        metrics.push_str(&format!("wraith_proxy_requests_total {}\n", total_requests));
    }

    // Upstream metrics
    if let Some(upstreams) = proxy_stats.get("upstreams") {
        if let Some(upstream_array) = upstreams.as_array() {
            metrics.push_str("# HELP wraith_upstream_healthy Upstream health status\n");
            metrics.push_str("# TYPE wraith_upstream_healthy gauge\n");

            for upstream in upstream_array {
                if let (Some(name), Some(healthy)) = (
                    upstream.get("name").and_then(|v| v.as_str()),
                    upstream.get("healthy").and_then(|v| v.as_bool())
                ) {
                    let health_value = if healthy { 1 } else { 0 };
                    metrics.push_str(&format!(
                        "wraith_upstream_healthy{{upstream=\"{}\"}} {}\n",
                        name, health_value
                    ));
                }
            }
        }
    }

    Ok(metrics)
}

async fn get_cert_info(
    State(admin): State<AdminServer>,
) -> Json<ApiResponse<serde_json::Value>> {
    // TODO: Implement certificate info retrieval
    let cert_info = serde_json::json!({
        "cert_path": admin.config.load().tls.cert_path,
        "key_path": admin.config.load().tls.key_path,
        "auto_cert": admin.config.load().tls.auto_cert,
        "expires_at": null,
        "issuer": null,
    });

    Json(ApiResponse {
        success: true,
        data: Some(cert_info),
        message: None,
    })
}

async fn renew_certificates(
    State(admin): State<AdminServer>,
) -> Result<Json<ApiResponse<String>>, StatusCode> {
    // TODO: Implement certificate renewal
    warn!("Certificate renewal not yet implemented");

    Ok(Json(ApiResponse {
        success: false,
        data: None,
        message: Some("Certificate renewal not yet implemented".to_string()),
    }))
}