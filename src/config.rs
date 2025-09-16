use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::Path;
use tokio::fs;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub server: ServerConfig,
    pub static_files: StaticConfig,
    pub admin: AdminConfig,
    #[serde(default)]
    pub proxy: ProxyConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    #[serde(default = "default_bind_address")]
    pub bind_address: String,
    #[serde(default = "default_port")]
    pub port: u16,
    #[serde(default = "default_max_connections")]
    pub max_connections: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StaticConfig {
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default = "default_static_root")]
    pub root: String,
    #[serde(default = "default_index_files")]
    pub index_files: Vec<String>,
    #[serde(default = "default_true")]
    pub compression: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AdminConfig {
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default = "default_admin_bind")]
    pub bind_address: String,
    #[serde(default = "default_admin_port")]
    pub port: u16,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProxyConfig {
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default)]
    pub upstreams: Vec<UpstreamConfig>,
    #[serde(default)]
    pub routes: Vec<RouteConfig>,
    #[serde(default)]
    pub load_balancing: LoadBalancingMethod,
    #[serde(default)]
    pub health_check: HealthCheckGlobalConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpstreamConfig {
    pub name: String,
    pub address: String,
    #[serde(default = "default_port")]
    pub port: u16,
    #[serde(default = "default_weight")]
    pub weight: u32,
    #[serde(default = "default_max_fails")]
    pub max_fails: usize,
    #[serde(default = "default_true")]
    pub enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RouteConfig {
    #[serde(default)]
    pub host: Option<String>,
    #[serde(default)]
    pub path: Option<String>,
    pub upstream: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum LoadBalancingMethod {
    RoundRobin,
    LeastConnections,
    Random,
    Weighted,
    IpHash,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthCheckGlobalConfig {
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default = "default_health_interval")]
    pub interval: std::time::Duration,
    #[serde(default = "default_health_timeout")]
    pub timeout: std::time::Duration,
    #[serde(default = "default_health_path")]
    pub path: String,
    #[serde(default = "default_health_status")]
    pub expected_status: u16,
}

impl Config {
    pub async fn from_file(path: &Path) -> Result<Self> {
        let contents = fs::read_to_string(path).await?;
        let config: Config = toml::from_str(&contents)?;
        Ok(config)
    }

    pub fn development() -> Self {
        Self {
            server: ServerConfig {
                bind_address: "127.0.0.1".to_string(),
                port: 8080,
                max_connections: 1000,
            },
            static_files: StaticConfig {
                enabled: true,
                root: "./public".to_string(),
                index_files: vec!["index.html".to_string(), "index.htm".to_string()],
                compression: true,
            },
            admin: AdminConfig {
                enabled: true,
                bind_address: "127.0.0.1".to_string(),
                port: 9090,
            },
            proxy: ProxyConfig {
                enabled: true,
                upstreams: vec![
                    UpstreamConfig {
                        name: "example".to_string(),
                        address: "httpbin.org".to_string(),
                        port: 80,
                        weight: 1,
                        max_fails: 3,
                        enabled: true,
                    },
                ],
                routes: vec![
                    RouteConfig {
                        host: None,
                        path: Some("/api/".to_string()),
                        upstream: "example".to_string(),
                    },
                ],
                load_balancing: LoadBalancingMethod::RoundRobin,
                health_check: HealthCheckGlobalConfig {
                    enabled: true,
                    interval: std::time::Duration::from_secs(30),
                    timeout: std::time::Duration::from_secs(5),
                    path: "/status/200".to_string(),
                    expected_status: 200,
                },
            },
        }
    }
}

impl Default for Config {
    fn default() -> Self {
        Self::development()
    }
}

// Default value functions
fn default_bind_address() -> String {
    "0.0.0.0".to_string()
}

fn default_port() -> u16 {
    8080
}

fn default_max_connections() -> u32 {
    10000
}

fn default_true() -> bool {
    true
}

fn default_static_root() -> String {
    "./public".to_string()
}

fn default_index_files() -> Vec<String> {
    vec!["index.html".to_string(), "index.htm".to_string()]
}

fn default_admin_bind() -> String {
    "127.0.0.1".to_string()
}

fn default_admin_port() -> u16 {
    9090
}

fn default_weight() -> u32 {
    1
}

fn default_max_fails() -> usize {
    3
}

fn default_health_interval() -> std::time::Duration {
    std::time::Duration::from_secs(30)
}

fn default_health_timeout() -> std::time::Duration {
    std::time::Duration::from_secs(5)
}

fn default_health_path() -> String {
    "/health".to_string()
}

fn default_health_status() -> u16 {
    200
}

impl Default for LoadBalancingMethod {
    fn default() -> Self {
        LoadBalancingMethod::RoundRobin
    }
}

impl Default for HealthCheckGlobalConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            interval: std::time::Duration::from_secs(30),
            timeout: std::time::Duration::from_secs(5),
            path: "/health".to_string(),
            expected_status: 200,
        }
    }
}

impl Default for ProxyConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            upstreams: vec![],
            routes: vec![],
            load_balancing: LoadBalancingMethod::default(),
            health_check: HealthCheckGlobalConfig::default(),
        }
    }
}