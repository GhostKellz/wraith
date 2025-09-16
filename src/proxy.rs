use crate::config::{LoadBalancingMethod, ProxyConfig, UpstreamConfig, RouteConfig};
use anyhow::{anyhow, Result};
use axum::{
    body::Body,
    extract::{Request, State},
    http::{StatusCode, Uri},
    response::Response,
};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tracing::{debug, error, info, warn};

#[derive(Clone)]
pub struct ProxyManager {
    config: ProxyConfig,
    upstreams: Arc<RwLock<Vec<Upstream>>>,
    load_balancer: LoadBalancer,
    request_counter: Arc<AtomicU64>,
    client: reqwest::Client,
}

#[derive(Debug, Clone)]
struct Upstream {
    config: UpstreamConfig,
    healthy: Arc<std::sync::atomic::AtomicBool>,
    active_connections: Arc<AtomicUsize>,
    total_requests: Arc<AtomicU64>,
    last_health_check: Arc<RwLock<Instant>>,
    current_fails: Arc<AtomicUsize>,
}

#[derive(Clone)]
struct LoadBalancer {
    method: LoadBalancingMethod,
    round_robin_counter: Arc<AtomicUsize>,
}

impl ProxyManager {
    pub async fn new(config: ProxyConfig) -> Result<Self> {
        let upstreams = config
            .upstreams
            .iter()
            .map(|config| Upstream {
                config: config.clone(),
                healthy: Arc::new(std::sync::atomic::AtomicBool::new(true)),
                active_connections: Arc::new(AtomicUsize::new(0)),
                total_requests: Arc::new(AtomicU64::new(0)),
                last_health_check: Arc::new(RwLock::new(Instant::now())),
                current_fails: Arc::new(AtomicUsize::new(0)),
            })
            .collect();

        let upstreams = Arc::new(RwLock::new(upstreams));

        let load_balancer = LoadBalancer {
            method: config.load_balancing.clone(),
            round_robin_counter: Arc::new(AtomicUsize::new(0)),
        };

        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .expect("Failed to create HTTP client");

        let proxy_manager = Self {
            config: config.clone(),
            upstreams: upstreams.clone(),
            load_balancer,
            request_counter: Arc::new(AtomicU64::new(0)),
            client,
        };

        // Start health checking task if enabled
        if config.health_check.enabled {
            let upstreams_clone = upstreams.clone();
            let health_checker = config.health_check.clone();
            tokio::spawn(async move {
                health_check_task(upstreams_clone, health_checker).await;
            });
        }

        Ok(proxy_manager)
    }

    pub async fn find_matching_route(&self, uri: &Uri, host: Option<&str>) -> Option<&RouteConfig> {
        for route in &self.config.routes {
            let path_matches = match &route.path {
                Some(route_path) => uri.path().starts_with(route_path),
                None => true,
            };

            let host_matches = match (&route.host, host) {
                (Some(route_host), Some(req_host)) => req_host == route_host,
                (None, _) => true,
                _ => false,
            };

            if path_matches && host_matches {
                return Some(route);
            }
        }
        None
    }

    pub async fn forward_request(
        &self,
        req: Request,
        upstream_name: &str,
    ) -> Result<Response<Body>, StatusCode> {
        let upstream = self.select_upstream(upstream_name).await
            .map_err(|e| {
                error!("Failed to select upstream: {}", e);
                StatusCode::BAD_GATEWAY
            })?;

        self.request_counter.fetch_add(1, Ordering::Relaxed);
        upstream.total_requests.fetch_add(1, Ordering::Relaxed);
        upstream.active_connections.fetch_add(1, Ordering::Relaxed);

        let result = self.forward_to_upstream(&upstream, req).await;

        upstream.active_connections.fetch_sub(1, Ordering::Relaxed);

        result
    }

    async fn select_upstream(&self, upstream_name: &str) -> Result<Upstream> {
        let upstreams = self.upstreams.read().await;

        // If specific upstream name is provided, try to find it
        if !upstream_name.is_empty() && upstream_name != "*" {
            if let Some(upstream) = upstreams.iter().find(|u| u.config.name == upstream_name) {
                if upstream.healthy.load(Ordering::Relaxed) {
                    return Ok(upstream.clone());
                }
            }
        }

        // Select using load balancing algorithm
        let healthy_upstreams: Vec<_> = upstreams
            .iter()
            .filter(|u| u.healthy.load(Ordering::Relaxed))
            .cloned()
            .collect();

        if healthy_upstreams.is_empty() {
            return Err(anyhow!("No healthy upstreams available"));
        }

        let selected = self.load_balancer.select(&healthy_upstreams)?;
        Ok(selected)
    }

    async fn forward_to_upstream(
        &self,
        upstream: &Upstream,
        req: Request,
    ) -> Result<Response<Body>, StatusCode> {
        let uri = req.uri().clone();
        let method = req.method().clone();
        let headers = req.headers().clone();

        // Build the upstream URL
        let upstream_url = format!(
            "http://{}:{}{}{}",
            upstream.config.address,
            upstream.config.port,
            uri.path(),
            uri.query().map(|q| format!("?{}", q)).unwrap_or_default()
        );

        debug!("Proxying {} request to: {}", method, upstream_url);

        // Convert axum request to reqwest request
        let mut reqwest_builder = self.client.request(method, &upstream_url);

        // Copy headers (excluding hop-by-hop headers)
        for (name, value) in headers.iter() {
            let name_str = name.as_str();
            if !is_hop_by_hop_header(name_str) {
                if let Ok(value_str) = value.to_str() {
                    reqwest_builder = reqwest_builder.header(name_str, value_str);
                }
            }
        }

        // Get the request body
        let body_bytes = axum::body::to_bytes(req.into_body(), usize::MAX).await
            .map_err(|e| {
                error!("Failed to read request body: {}", e);
                StatusCode::BAD_REQUEST
            })?;

        if !body_bytes.is_empty() {
            reqwest_builder = reqwest_builder.body(body_bytes.to_vec());
        }

        // Send the request
        let response = reqwest_builder.send().await
            .map_err(|e| {
                error!("Proxy request failed: {}", e);
                StatusCode::BAD_GATEWAY
            })?;

        // Convert reqwest response to axum response
        let status = response.status();
        let mut builder = Response::builder().status(status);

        // Copy response headers
        for (name, value) in response.headers().iter() {
            let name_str = name.as_str();
            if !is_hop_by_hop_header(name_str) {
                builder = builder.header(name, value);
            }
        }

        let body_bytes = response.bytes().await
            .map_err(|e| {
                error!("Failed to read response body: {}", e);
                StatusCode::BAD_GATEWAY
            })?;

        let response = builder
            .body(Body::from(body_bytes))
            .map_err(|e| {
                error!("Failed to build response: {}", e);
                StatusCode::INTERNAL_SERVER_ERROR
            })?;

        debug!("Proxy response status: {}", status);
        Ok(response)
    }

    pub async fn get_stats(&self) -> HashMap<String, serde_json::Value> {
        let mut stats = HashMap::new();
        let upstreams = self.upstreams.read().await;

        stats.insert(
            "total_requests".to_string(),
            self.request_counter.load(Ordering::Relaxed).into(),
        );

        let upstream_stats: Vec<_> = upstreams
            .iter()
            .map(|u| {
                serde_json::json!({
                    "name": u.config.name,
                    "address": format!("{}:{}", u.config.address, u.config.port),
                    "healthy": u.healthy.load(Ordering::Relaxed),
                    "active_connections": u.active_connections.load(Ordering::Relaxed),
                    "total_requests": u.total_requests.load(Ordering::Relaxed),
                    "current_fails": u.current_fails.load(Ordering::Relaxed),
                })
            })
            .collect();

        stats.insert("upstreams".to_string(), upstream_stats.into());
        stats
    }
}

impl LoadBalancer {
    fn select(&self, upstreams: &[Upstream]) -> Result<Upstream> {
        match self.method {
            LoadBalancingMethod::RoundRobin => {
                let index = self.round_robin_counter.fetch_add(1, Ordering::Relaxed);
                Ok(upstreams[index % upstreams.len()].clone())
            }

            LoadBalancingMethod::LeastConnections => {
                let upstream = upstreams
                    .iter()
                    .min_by_key(|u| u.active_connections.load(Ordering::Relaxed))
                    .ok_or_else(|| anyhow!("No upstreams available"))?;
                Ok(upstream.clone())
            }

            LoadBalancingMethod::Random => {
                use rand::Rng;
                let index = rand::thread_rng().gen_range(0..upstreams.len());
                Ok(upstreams[index].clone())
            }

            LoadBalancingMethod::Weighted => {
                // Simple weighted round-robin
                let total_weight: u32 = upstreams.iter().map(|u| u.config.weight).sum();
                let mut target = (self.round_robin_counter.fetch_add(1, Ordering::Relaxed) as u32)
                    % total_weight;

                for upstream in upstreams {
                    if target < upstream.config.weight {
                        return Ok(upstream.clone());
                    }
                    target -= upstream.config.weight;
                }

                // Fallback
                Ok(upstreams[0].clone())
            }

            LoadBalancingMethod::IpHash => {
                // For now, just use round-robin
                let index = self.round_robin_counter.fetch_add(1, Ordering::Relaxed);
                Ok(upstreams[index % upstreams.len()].clone())
            }
        }
    }
}

fn is_hop_by_hop_header(name: &str) -> bool {
    matches!(
        name.to_lowercase().as_str(),
        "connection" | "upgrade" | "proxy-authorization" | "proxy-authenticate"
        | "te" | "trailer" | "transfer-encoding"
    )
}

async fn health_check_task(
    upstreams: Arc<RwLock<Vec<Upstream>>>,
    health_checker: crate::config::HealthCheckGlobalConfig,
) {
    let mut interval = tokio::time::interval(health_checker.interval);

    loop {
        interval.tick().await;

        let upstreams = upstreams.read().await;
        for upstream in upstreams.iter() {
            let upstream = upstream.clone();
            let health_checker = health_checker.clone();

            tokio::spawn(async move {
                if let Err(e) = check_upstream_health(&upstream, &health_checker).await {
                    debug!("Health check failed for {}: {}", upstream.config.name, e);
                    upstream.current_fails.fetch_add(1, Ordering::Relaxed);

                    if upstream.current_fails.load(Ordering::Relaxed) >= upstream.config.max_fails {
                        upstream.healthy.store(false, Ordering::Relaxed);
                        warn!("Marking upstream {} as unhealthy", upstream.config.name);
                    }
                } else {
                    upstream.current_fails.store(0, Ordering::Relaxed);
                    if !upstream.healthy.load(Ordering::Relaxed) {
                        upstream.healthy.store(true, Ordering::Relaxed);
                        info!("Marking upstream {} as healthy", upstream.config.name);
                    }
                }

                *upstream.last_health_check.write().await = Instant::now();
            });
        }
    }
}

async fn check_upstream_health(
    upstream: &Upstream,
    health_checker: &crate::config::HealthCheckGlobalConfig,
) -> Result<()> {
    let url = format!(
        "http://{}:{}{}",
        upstream.config.address,
        upstream.config.port,
        health_checker.path
    );

    let client = reqwest::Client::builder()
        .timeout(health_checker.timeout)
        .build()?;

    let response = client
        .get(&url)
        .header("user-agent", "wraith-health-check/1.0")
        .send()
        .await?;

    if response.status().as_u16() == health_checker.expected_status {
        Ok(())
    } else {
        Err(anyhow!(
            "Unexpected status code: {}",
            response.status()
        ))
    }
}

// Proxy handler for axum routing
pub async fn proxy_handler(
    State(proxy_manager): State<Arc<ProxyManager>>,
    req: Request,
) -> Result<Response<Body>, StatusCode> {
    let uri = req.uri().clone();
    let method = req.method().clone();
    let host = req
        .headers()
        .get("host")
        .and_then(|h| h.to_str().ok());

    info!("Processing proxy request: {} {}", method, uri);

    // Find matching route
    let route = match proxy_manager.find_matching_route(&uri, host).await {
        Some(route) => route,
        None => {
            debug!("No matching route found for: {}", uri);
            return Err(StatusCode::NOT_FOUND);
        }
    };

    debug!("Found matching route for upstream: {}", route.upstream);

    // Forward the request
    proxy_manager.forward_request(req, &route.upstream).await
}