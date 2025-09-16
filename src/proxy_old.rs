use crate::config::{LoadBalancingMethod, ProxyConfig, UpstreamConfig};
use anyhow::Result;
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
    upstreams: Arc<RwLock<Vec<Upstream>>>,
    load_balancer: LoadBalancer,
    health_checker: HealthChecker,
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

#[derive(Clone)]
struct HealthChecker {
    enabled: bool,
    interval: Duration,
    timeout: Duration,
    path: String,
    expected_status: u16,
}

impl ProxyManager {
    pub async fn new(config: ProxyConfig) -> Result<Self> {
        let upstreams = config
            .upstreams
            .into_iter()
            .map(|config| Upstream {
                config,
                healthy: Arc::new(std::sync::atomic::AtomicBool::new(true)),
                active_connections: Arc::new(AtomicUsize::new(0)),
                total_requests: Arc::new(AtomicU64::new(0)),
                last_health_check: Arc::new(RwLock::new(Instant::now())),
                current_fails: Arc::new(AtomicUsize::new(0)),
            })
            .collect();

        let upstreams = Arc::new(RwLock::new(upstreams));

        let load_balancer = LoadBalancer {
            method: config.load_balancing,
            round_robin_counter: Arc::new(AtomicUsize::new(0)),
        };

        let health_checker = HealthChecker {
            enabled: config.health_check.enabled,
            interval: config.health_check.interval,
            timeout: config.health_check.timeout,
            path: config.health_check.path,
            expected_status: config.health_check.expected_status,
        };

        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .expect("Failed to create HTTP client");

        let proxy_manager = Self {
            upstreams: upstreams.clone(),
            load_balancer,
            health_checker: health_checker.clone(),
            request_counter: Arc::new(AtomicU64::new(0)),
            client,
        };

        // Start health checking task
        if health_checker.enabled {
            let upstreams_clone = upstreams.clone();
            let health_checker_clone = health_checker.clone();
            tokio::spawn(async move {
                health_check_task(upstreams_clone, health_checker_clone).await;
            });
        }

        Ok(proxy_manager)
    }

    pub async fn forward_request(
        &self,
        req: Request,
        upstream_name: &str,
    ) -> Result<Response<Body>, StatusCode> {
        let upstream = self.select_upstream(upstream_name).await
            .map_err(|_| StatusCode::BAD_GATEWAY)?;

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
            return Err(anyhow::anyhow!("No healthy upstreams available"));
        }

        let selected = self.load_balancer.select(&healthy_upstreams)?;
        Ok(selected)
    }

    async fn forward_to_upstream(
        &self,
        upstream: &Upstream,
        req: Request<()>,
        peer_addr: SocketAddr,
    ) -> Result<(Response<()>, Option<Bytes>)> {
        let target_addr = format!("{}:{}", upstream.config.address, upstream.config.port);

        debug!(
            "Forwarding request to upstream {} ({})",
            upstream.config.name, target_addr
        );

        // Connect to upstream
        let stream = timeout(
            Duration::from_secs(5),
            TcpStream::connect(&target_addr),
        )
        .await
        .map_err(|_| anyhow::anyhow!("Connection timeout"))?
        .map_err(|e| {
            warn!("Failed to connect to upstream {}: {}", target_addr, e);
            anyhow::anyhow!("Connection failed: {}", e)
        })?;

        let io = TokioIo::new(stream);

        // Build request for upstream
        let (parts, _) = req.into_parts();
        let mut upstream_req = Request::from_parts(parts, http_body_util::Empty::<Bytes>::new());

        // Add/modify headers
        upstream_req.headers_mut().insert(
            "x-forwarded-for",
            peer_addr.ip().to_string().parse()?,
        );
        upstream_req.headers_mut().insert(
            "x-forwarded-proto",
            "https".parse()?,
        );

        // Try HTTP/2 first, fallback to HTTP/1
        match self.send_http2_request(io, upstream_req).await {
            Ok(response) => Ok(response),
            Err(e) => {
                debug!("HTTP/2 failed, trying HTTP/1: {}", e);
                // Reconnect for HTTP/1
                let stream = TcpStream::connect(&target_addr).await?;
                let io = TokioIo::new(stream);
                self.send_http1_request(io, upstream_req).await
            }
        }
    }

    async fn send_http2_request(
        &self,
        io: TokioIo<TcpStream>,
        req: Request<http_body_util::Empty<Bytes>>,
    ) -> Result<(Response<()>, Option<Bytes>)> {
        let (mut sender, conn) = http2::handshake(io).await?;

        // Spawn connection task
        tokio::spawn(async move {
            if let Err(e) = conn.await {
                error!("HTTP/2 connection error: {}", e);
            }
        });

        let response = sender.send_request(req).await?;
        let (parts, body) = response.into_parts();
        let body_bytes = http_body_util::BodyExt::collect(body).await?.to_bytes();

        Ok((Response::from_parts(parts, ()), Some(body_bytes)))
    }

    async fn send_http1_request(
        &self,
        io: TokioIo<TcpStream>,
        req: Request<http_body_util::Empty<Bytes>>,
    ) -> Result<(Response<()>, Option<Bytes>)> {
        let (mut sender, conn) = http1::handshake(io).await?;

        // Spawn connection task
        tokio::spawn(async move {
            if let Err(e) = conn.await {
                error!("HTTP/1 connection error: {}", e);
            }
        });

        let response = sender.send_request(req).await?;
        let (parts, body) = response.into_parts();
        let body_bytes = http_body_util::BodyExt::collect(body).await?.to_bytes();

        Ok((Response::from_parts(parts, ()), Some(body_bytes)))
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
                    .ok_or_else(|| anyhow::anyhow!("No upstreams available"))?;
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

async fn health_check_task(
    upstreams: Arc<RwLock<Vec<Upstream>>>,
    health_checker: HealthChecker,
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
    health_checker: &HealthChecker,
) -> Result<()> {
    let addr = format!("{}:{}", upstream.config.address, upstream.config.port);
    let uri: Uri = format!("http://{}{}", addr, health_checker.path).parse()?;

    let stream = timeout(health_checker.timeout, TcpStream::connect(&addr)).await??;
    let io = TokioIo::new(stream);

    let (mut sender, conn) = http1::handshake(io).await?;

    tokio::spawn(async move {
        if let Err(e) = conn.await {
            debug!("Health check connection error: {}", e);
        }
    });

    let req = Request::builder()
        .method("GET")
        .uri(uri)
        .header("user-agent", "wraith-health-check/1.0")
        .body(http_body_util::Empty::<Bytes>::new())?;

    let response = timeout(health_checker.timeout, sender.send_request(req)).await??;

    if response.status().as_u16() == health_checker.expected_status {
        Ok(())
    } else {
        Err(anyhow::anyhow!(
            "Unexpected status code: {}",
            response.status()
        ))
    }
}