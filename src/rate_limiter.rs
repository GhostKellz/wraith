use crate::config::{RateLimitConfig, DdosConfig};
use anyhow::Result;
use governor::{Quota, RateLimiter as GovernorRateLimiter, DefaultDirectRateLimiter};
use nonzero_ext::*;
use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tracing::{debug, warn, info};

#[derive(Clone)]
pub struct RateLimiter {
    config: RateLimitConfig,
    ddos_config: DdosConfig,
    global_limiter: Arc<DefaultDirectRateLimiter>,
    per_ip_limiters: Arc<RwLock<HashMap<IpAddr, Arc<DefaultDirectRateLimiter>>>>,
    blocked_ips: Arc<RwLock<HashMap<IpAddr, BlockedClient>>>,
    connection_counts: Arc<RwLock<HashMap<IpAddr, ConnectionTracker>>>,
}

#[derive(Debug, Clone)]
struct BlockedClient {
    blocked_until: Instant,
    reason: BlockReason,
    block_count: u32,
}

#[derive(Debug, Clone)]
enum BlockReason {
    RateLimit,
    TooManyConnections,
    DdosDetection,
    Blacklisted,
}

#[derive(Debug, Clone)]
struct ConnectionTracker {
    active_connections: u32,
    last_connection: Instant,
    connection_rate: Vec<Instant>,
}

#[derive(Debug)]
pub struct RateLimitResult {
    pub allowed: bool,
    pub reason: RateLimitReason,
    pub retry_after: Option<Duration>,
    pub remaining: Option<u32>,
}

#[derive(Debug, Clone)]
pub enum RateLimitReason {
    Allowed,
    RateLimit,
    GlobalLimit,
    Blocked,
    TooManyConnections,
    Blacklisted,
    Whitelisted,
}

impl RateLimiter {
    pub fn new(rate_config: RateLimitConfig, ddos_config: DdosConfig) -> Self {
        // Create global rate limiter
        let global_quota = Quota::per_minute(nonzero!(rate_config.requests_per_minute))
            .allow_burst(nonzero!(rate_config.burst));
        let global_limiter = Arc::new(DefaultDirectRateLimiter::new(global_quota));

        Self {
            config: rate_config,
            ddos_config,
            global_limiter,
            per_ip_limiters: Arc::new(RwLock::new(HashMap::new())),
            blocked_ips: Arc::new(RwLock::new(HashMap::new())),
            connection_counts: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    pub async fn check_request(
        &self,
        client_ip: IpAddr,
        request_size: Option<usize>,
    ) -> Result<RateLimitResult> {
        if !self.config.enabled {
            return Ok(RateLimitResult {
                allowed: true,
                reason: RateLimitReason::Allowed,
                retry_after: None,
                remaining: None,
            });
        }

        // Check if IP is whitelisted
        if self.is_whitelisted(client_ip) {
            return Ok(RateLimitResult {
                allowed: true,
                reason: RateLimitReason::Whitelisted,
                retry_after: None,
                remaining: None,
            });
        }

        // Check if IP is blacklisted
        if self.is_blacklisted(client_ip) {
            return Ok(RateLimitResult {
                allowed: false,
                reason: RateLimitReason::Blacklisted,
                retry_after: None,
                remaining: Some(0),
            });
        }

        // Check if IP is currently blocked
        if let Some(result) = self.check_blocked_ip(client_ip).await {
            return Ok(result);
        }

        // Check request size limits
        if let Some(size) = request_size {
            if size > self.config.max_request_size {
                self.block_ip(client_ip, BlockReason::RateLimit, Duration::from_secs(300)).await;
                return Ok(RateLimitResult {
                    allowed: false,
                    reason: RateLimitReason::RateLimit,
                    retry_after: Some(Duration::from_secs(300)),
                    remaining: Some(0),
                });
            }
        }

        // Check global rate limit
        if let Err(_) = self.global_limiter.check() {
            debug!("Global rate limit exceeded");
            return Ok(RateLimitResult {
                allowed: false,
                reason: RateLimitReason::GlobalLimit,
                retry_after: Some(Duration::from_secs(60)),
                remaining: Some(0),
            });
        }

        // Check per-IP rate limit
        let per_ip_result = self.check_per_ip_limit(client_ip).await?;
        if !per_ip_result.allowed {
            // Auto-block if enabled
            if self.config.auto_block_enabled {
                self.block_ip(client_ip, BlockReason::RateLimit, self.config.block_duration).await;
            }
            return Ok(per_ip_result);
        }

        // Check DDoS protection
        if self.ddos_config.enabled {
            if let Some(result) = self.check_ddos_protection(client_ip).await {
                return Ok(result);
            }
        }

        Ok(RateLimitResult {
            allowed: true,
            reason: RateLimitReason::Allowed,
            retry_after: None,
            remaining: per_ip_result.remaining,
        })
    }

    pub async fn track_connection(&self, client_ip: IpAddr, connected: bool) -> Result<bool> {
        if !self.ddos_config.enabled {
            return Ok(true);
        }

        let mut connection_counts = self.connection_counts.write().await;
        let now = Instant::now();

        let tracker = connection_counts
            .entry(client_ip)
            .or_insert_with(|| ConnectionTracker {
                active_connections: 0,
                last_connection: now,
                connection_rate: Vec::new(),
            });

        if connected {
            tracker.active_connections += 1;
            tracker.last_connection = now;
            tracker.connection_rate.push(now);

            // Clean old connection rate entries
            tracker.connection_rate.retain(|&time| {
                now.duration_since(time) <= Duration::from_secs(60)
            });

            // Check connection limits
            if tracker.active_connections > self.ddos_config.max_connections_per_ip {
                warn!(
                    "IP {} exceeded max connections: {}",
                    client_ip, tracker.active_connections
                );
                self.block_ip(client_ip, BlockReason::TooManyConnections, Duration::from_secs(600)).await;
                return Ok(false);
            }

            // Check connection rate
            if tracker.connection_rate.len() as u32 > self.ddos_config.connection_rate_limit {
                warn!(
                    "IP {} exceeded connection rate: {} connections/min",
                    client_ip,
                    tracker.connection_rate.len()
                );
                self.block_ip(client_ip, BlockReason::DdosDetection, Duration::from_secs(1800)).await;
                return Ok(false);
            }
        } else {
            tracker.active_connections = tracker.active_connections.saturating_sub(1);
        }

        Ok(true)
    }

    async fn check_per_ip_limit(&self, client_ip: IpAddr) -> Result<RateLimitResult> {
        let limiters = self.per_ip_limiters.read().await;

        if let Some(limiter) = limiters.get(&client_ip) {
            match limiter.check() {
                Ok(_) => Ok(RateLimitResult {
                    allowed: true,
                    reason: RateLimitReason::Allowed,
                    retry_after: None,
                    remaining: None, // TODO: Get remaining from governor
                }),
                Err(_) => Ok(RateLimitResult {
                    allowed: false,
                    reason: RateLimitReason::RateLimit,
                    retry_after: Some(Duration::from_secs(60)),
                    remaining: Some(0),
                }),
            }
        } else {
            // Create new limiter for this IP
            drop(limiters);
            let mut limiters = self.per_ip_limiters.write().await;

            let quota = Quota::per_minute(nonzero!(self.config.requests_per_minute))
                .allow_burst(nonzero!(self.config.burst));
            let limiter = Arc::new(DefaultDirectRateLimiter::new(quota));

            // Check the new limiter
            let result = match limiter.check() {
                Ok(_) => RateLimitResult {
                    allowed: true,
                    reason: RateLimitReason::Allowed,
                    retry_after: None,
                    remaining: None,
                },
                Err(_) => RateLimitResult {
                    allowed: false,
                    reason: RateLimitReason::RateLimit,
                    retry_after: Some(Duration::from_secs(60)),
                    remaining: Some(0),
                },
            };

            limiters.insert(client_ip, limiter);
            Ok(result)
        }
    }

    async fn check_blocked_ip(&self, client_ip: IpAddr) -> Option<RateLimitResult> {
        let mut blocked_ips = self.blocked_ips.write().await;

        if let Some(blocked) = blocked_ips.get(&client_ip) {
            if Instant::now() < blocked.blocked_until {
                let retry_after = blocked.blocked_until.duration_since(Instant::now());
                return Some(RateLimitResult {
                    allowed: false,
                    reason: RateLimitReason::Blocked,
                    retry_after: Some(retry_after),
                    remaining: Some(0),
                });
            } else {
                // Block expired, remove it
                blocked_ips.remove(&client_ip);
                info!("Unblocked IP: {}", client_ip);
            }
        }

        None
    }

    async fn check_ddos_protection(&self, client_ip: IpAddr) -> Option<RateLimitResult> {
        let connection_counts = self.connection_counts.read().await;

        if let Some(tracker) = connection_counts.get(&client_ip) {
            if tracker.active_connections > self.ddos_config.max_connections_per_ip {
                return Some(RateLimitResult {
                    allowed: false,
                    reason: RateLimitReason::TooManyConnections,
                    retry_after: Some(Duration::from_secs(60)),
                    remaining: Some(0),
                });
            }
        }

        None
    }

    async fn block_ip(&self, client_ip: IpAddr, reason: BlockReason, duration: Duration) {
        let mut blocked_ips = self.blocked_ips.write().await;
        let blocked_until = Instant::now() + duration;

        let block_count = if let Some(existing) = blocked_ips.get(&client_ip) {
            existing.block_count + 1
        } else {
            1
        };

        blocked_ips.insert(client_ip, BlockedClient {
            blocked_until,
            reason: reason.clone(),
            block_count,
        });

        warn!(
            "Blocked IP {} for {:?} (reason: {:?}, count: {})",
            client_ip,
            duration,
            reason,
            block_count
        );
    }

    fn is_whitelisted(&self, client_ip: IpAddr) -> bool {
        self.config.whitelist.iter().any(|ip_str| {
            ip_str.parse::<IpAddr>().map_or(false, |ip| ip == client_ip)
        })
    }

    fn is_blacklisted(&self, client_ip: IpAddr) -> bool {
        self.config.blacklist.iter().any(|ip_str| {
            ip_str.parse::<IpAddr>().map_or(false, |ip| ip == client_ip)
        })
    }

    pub async fn get_stats(&self) -> HashMap<String, serde_json::Value> {
        let mut stats = HashMap::new();

        let blocked_ips = self.blocked_ips.read().await;
        let connection_counts = self.connection_counts.read().await;
        let per_ip_limiters = self.per_ip_limiters.read().await;

        stats.insert("blocked_ips_count".to_string(), blocked_ips.len().into());
        stats.insert("tracked_ips_count".to_string(), per_ip_limiters.len().into());
        stats.insert("active_connections_count".to_string(),
            connection_counts.values().map(|t| t.active_connections).sum::<u32>().into());

        let blocked_ips_info: Vec<_> = blocked_ips.iter().map(|(ip, blocked)| {
            serde_json::json!({
                "ip": ip.to_string(),
                "blocked_until": blocked.blocked_until.elapsed().as_secs(),
                "reason": format!("{:?}", blocked.reason),
                "block_count": blocked.block_count,
            })
        }).collect();

        stats.insert("blocked_ips".to_string(), blocked_ips_info.into());
        stats
    }

    pub async fn unblock_ip(&self, client_ip: IpAddr) -> bool {
        let mut blocked_ips = self.blocked_ips.write().await;
        if blocked_ips.remove(&client_ip).is_some() {
            info!("Manually unblocked IP: {}", client_ip);
            true
        } else {
            false
        }
    }

    pub async fn cleanup_expired(&self) {
        let now = Instant::now();

        // Clean up expired blocked IPs
        {
            let mut blocked_ips = self.blocked_ips.write().await;
            blocked_ips.retain(|ip, blocked| {
                let should_keep = now < blocked.blocked_until;
                if !should_keep {
                    debug!("Cleaned up expired block for IP: {}", ip);
                }
                should_keep
            });
        }

        // Clean up old connection trackers
        {
            let mut connection_counts = self.connection_counts.write().await;
            connection_counts.retain(|ip, tracker| {
                let should_keep = tracker.active_connections > 0
                    || now.duration_since(tracker.last_connection) < Duration::from_secs(3600);
                if !should_keep {
                    debug!("Cleaned up connection tracker for IP: {}", ip);
                }
                should_keep
            });
        }

        // Clean up old per-IP limiters
        {
            let mut per_ip_limiters = self.per_ip_limiters.write().await;
            let old_count = per_ip_limiters.len();
            // Keep only recent limiters (this is a simple heuristic)
            if per_ip_limiters.len() > 10000 {
                per_ip_limiters.clear();
                debug!("Cleared {} old per-IP limiters", old_count);
            }
        }
    }
}

// Spawn cleanup task
pub fn spawn_cleanup_task(rate_limiter: Arc<RateLimiter>) {
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(300)); // 5 minutes

        loop {
            interval.tick().await;
            rate_limiter.cleanup_expired().await;
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::Ipv4Addr;

    #[tokio::test]
    async fn test_rate_limiter_basic() {
        let config = RateLimitConfig {
            enabled: true,
            requests_per_minute: 60,
            burst: 10,
            max_request_size: 1024 * 1024,
            whitelist: vec![],
            blacklist: vec![],
            auto_block_enabled: false,
            block_duration: Duration::from_secs(300),
        };

        let ddos_config = DdosConfig {
            enabled: false,
            max_connections_per_ip: 100,
            connection_rate_limit: 10,
            packet_rate_limit: 1000,
            window_size: Duration::from_secs(60),
        };

        let limiter = RateLimiter::new(config, ddos_config);
        let ip = IpAddr::V4(Ipv4Addr::new(192, 168, 1, 1));

        let result = limiter.check_request(ip, None).await.unwrap();
        assert!(result.allowed);
        assert!(matches!(result.reason, RateLimitReason::Allowed));
    }

    #[tokio::test]
    async fn test_whitelist() {
        let config = RateLimitConfig {
            enabled: true,
            requests_per_minute: 1, // Very low limit
            burst: 1,
            max_request_size: 1024 * 1024,
            whitelist: vec!["192.168.1.1".to_string()],
            blacklist: vec![],
            auto_block_enabled: false,
            block_duration: Duration::from_secs(300),
        };

        let ddos_config = DdosConfig {
            enabled: false,
            max_connections_per_ip: 100,
            connection_rate_limit: 10,
            packet_rate_limit: 1000,
            window_size: Duration::from_secs(60),
        };

        let limiter = RateLimiter::new(config, ddos_config);
        let ip = IpAddr::V4(Ipv4Addr::new(192, 168, 1, 1));

        let result = limiter.check_request(ip, None).await.unwrap();
        assert!(result.allowed);
        assert!(matches!(result.reason, RateLimitReason::Whitelisted));
    }
}