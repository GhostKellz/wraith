use crate::{config::Config, proxy::ProxyManager, static_server::StaticFileServer};
use anyhow::Result;
use bytes::Bytes;
use http::{Method, Request, Response, StatusCode};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use tracing::{debug, info};

#[derive(Clone)]
pub struct Router {
    config: Config,
    routes: Vec<Route>,
    static_server: Arc<StaticFileServer>,
}

#[derive(Clone)]
struct Route {
    path_pattern: String,
    host_pattern: Option<String>,
    methods: Vec<Method>,
    handler: RouteHandler,
    priority: u32,
}

#[derive(Clone)]
enum RouteHandler {
    Proxy { upstream_name: String },
    Static,
    Health,
    Admin,
}

impl Router {
    pub fn new(config: Config) -> Self {
        let mut routes = Vec::new();

        // Add health check route
        routes.push(Route {
            path_pattern: "/health".to_string(),
            host_pattern: None,
            methods: vec![Method::GET],
            handler: RouteHandler::Health,
            priority: 100,
        });

        // Add proxy routes from config
        if config.proxy.enabled {
            for upstream in &config.proxy.upstreams {
                routes.push(Route {
                    path_pattern: "/*".to_string(),
                    host_pattern: None,
                    methods: vec![],
                    handler: RouteHandler::Proxy {
                        upstream_name: upstream.name.clone(),
                    },
                    priority: 50,
                });
            }
        }

        // Add static file route
        if config.static_files.enabled {
            routes.push(Route {
                path_pattern: "/*".to_string(),
                host_pattern: None,
                methods: vec![Method::GET, Method::HEAD],
                handler: RouteHandler::Static,
                priority: 10,
            });
        }

        // Sort routes by priority (higher first)
        routes.sort_by(|a, b| b.priority.cmp(&a.priority));

        let static_server = Arc::new(StaticFileServer::new(config.static_files.clone()));

        Self {
            config,
            routes,
            static_server,
        }
    }

    pub async fn route_request(
        &self,
        req: Request<()>,
        peer_addr: SocketAddr,
        proxy_manager: Arc<ProxyManager>,
    ) -> Result<(Response<()>, Option<Bytes>)> {
        let path = req.uri().path();
        let method = req.method();
        let host = req
            .headers()
            .get("host")
            .and_then(|h| h.to_str().ok())
            .map(|s| s.to_string());

        debug!(
            "Routing request: {} {} from {}",
            method, path, peer_addr
        );

        // Find matching route
        for route in &self.routes {
            if self.route_matches(&route, path, method, host.as_deref()) {
                return self
                    .handle_route(&route, req, peer_addr, proxy_manager)
                    .await;
            }
        }

        // No route found
        Ok((
            Response::builder()
                .status(StatusCode::NOT_FOUND)
                .body(())?,
            Some(Bytes::from("Not Found")),
        ))
    }

    fn route_matches(
        &self,
        route: &Route,
        path: &str,
        method: &Method,
        host: Option<&str>,
    ) -> bool {
        // Check method
        if !route.methods.is_empty() && !route.methods.contains(method) {
            return false;
        }

        // Check host
        if let Some(ref host_pattern) = route.host_pattern {
            if host.is_none() || !self.pattern_matches(host_pattern, host.unwrap()) {
                return false;
            }
        }

        // Check path
        self.pattern_matches(&route.path_pattern, path)
    }

    fn pattern_matches(&self, pattern: &str, path: &str) -> bool {
        if pattern == path {
            return true;
        }

        // Wildcard matching
        if pattern.ends_with("/*") {
            let prefix = &pattern[..pattern.len() - 2];
            return path.starts_with(prefix);
        }

        // Parameter matching (simplified)
        if pattern.contains(':') {
            let pattern_parts: Vec<&str> = pattern.split('/').collect();
            let path_parts: Vec<&str> = path.split('/').collect();

            if pattern_parts.len() != path_parts.len() {
                return false;
            }

            for (pattern_part, path_part) in pattern_parts.iter().zip(path_parts.iter()) {
                if !pattern_part.starts_with(':') && pattern_part != path_part {
                    return false;
                }
            }

            return true;
        }

        false
    }

    async fn handle_route(
        &self,
        route: &Route,
        req: Request<()>,
        peer_addr: SocketAddr,
        proxy_manager: Arc<ProxyManager>,
    ) -> Result<(Response<()>, Option<Bytes>)> {
        match &route.handler {
            RouteHandler::Health => Ok((
                Response::builder()
                    .status(StatusCode::OK)
                    .header("content-type", "application/json")
                    .body(())?,
                Some(Bytes::from(r#"{"status":"healthy"}"#)),
            )),

            RouteHandler::Static => {
                let path = req.uri().path();
                self.static_server.serve_file(path, req.headers()).await
            }

            RouteHandler::Proxy { upstream_name } => {
                proxy_manager
                    .forward_request(req, upstream_name, peer_addr)
                    .await
            }

            RouteHandler::Admin => Ok((
                Response::builder()
                    .status(StatusCode::OK)
                    .body(())?,
                Some(Bytes::from("Admin endpoint")),
            )),
        }
    }

    pub fn add_route(
        &mut self,
        path: String,
        host: Option<String>,
        methods: Vec<Method>,
        upstream: String,
        priority: u32,
    ) {
        self.routes.push(Route {
            path_pattern: path,
            host_pattern: host,
            methods,
            handler: RouteHandler::Proxy {
                upstream_name: upstream,
            },
            priority,
        });

        // Re-sort routes
        self.routes.sort_by(|a, b| b.priority.cmp(&a.priority));
    }

    pub fn remove_route(&mut self, path: &str, host: Option<&str>) {
        self.routes.retain(|route| {
            !(route.path_pattern == path
                && route.host_pattern.as_deref() == host)
        });
    }

    pub fn list_routes(&self) -> Vec<RouteInfo> {
        self.routes
            .iter()
            .map(|route| RouteInfo {
                path: route.path_pattern.clone(),
                host: route.host_pattern.clone(),
                methods: route
                    .methods
                    .iter()
                    .map(|m| m.to_string())
                    .collect(),
                handler_type: match &route.handler {
                    RouteHandler::Proxy { upstream_name } => {
                        format!("proxy:{}", upstream_name)
                    }
                    RouteHandler::Static => "static".to_string(),
                    RouteHandler::Health => "health".to_string(),
                    RouteHandler::Admin => "admin".to_string(),
                },
                priority: route.priority,
            })
            .collect()
    }
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct RouteInfo {
    pub path: String,
    pub host: Option<String>,
    pub methods: Vec<String>,
    pub handler_type: String,
    pub priority: u32,
}