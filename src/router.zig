//! Advanced Router module for Wraith
//! Handles HTTP/3 request routing with host/path/header matching

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Router = struct {
    allocator: Allocator,
    routes: std.ArrayList(Route),
    middleware: std.ArrayList(Middleware),
    
    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .routes = std.ArrayList(Route).init(allocator),
            .middleware = std.ArrayList(Middleware).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.routes.items) |route| {
            self.allocator.free(route.path);
            if (route.host) |host| {
                self.allocator.free(host);
            }
        }
        self.routes.deinit();
        self.middleware.deinit();
    }

    pub fn addRoute(self: *Self, config: RouteConfig) !void {
        const route = Route{
            .path = try self.allocator.dupe(u8, config.path),
            .host = if (config.host) |h| try self.allocator.dupe(u8, h) else null,
            .method = config.method,
            .handler = config.handler,
            .route_type = config.route_type,
            .priority = config.priority,
            .middleware = config.middleware,
        };
        
        try self.routes.append(route);
        
        // Sort routes by priority (higher priority first)
        std.sort.insertion(Route, self.routes.items, {}, routePriorityLessThan);
    }
    
    fn routePriorityLessThan(_: void, a: Route, b: Route) bool {
        return a.priority > b.priority;
    }

    pub fn match(self: *Self, request: *const RoutingRequest) ?RouteMatch {
        for (self.routes.items) |*route| {
            if (self.routeMatches(route, request)) {
                return RouteMatch{
                    .route = route,
                    .params = self.extractParams(route, request) catch null,
                };
            }
        }
        return null;
    }
    
    fn routeMatches(self: *Self, route: *const Route, request: *const RoutingRequest) bool {
        // Method matching
        if (route.method != .ANY and route.method != request.method) {
            return false;
        }
        
        // Host matching
        if (route.host) |expected_host| {
            if (request.host == null or !std.mem.eql(u8, expected_host, request.host.?)) {
                return false;
            }
        }
        
        // Path matching
        return self.pathMatches(route.path, request.path);
    }
    
    fn pathMatches(self: *Self, pattern: []const u8, path: []const u8) bool {
        _ = self;
        
        // Exact match
        if (std.mem.eql(u8, pattern, path)) {
            return true;
        }
        
        // Wildcard matching
        if (std.mem.endsWith(u8, pattern, "/*")) {
            const prefix = pattern[0..pattern.len - 2];
            return std.mem.startsWith(u8, path, prefix);
        }
        
        // Parameter matching (e.g., /users/:id)
        if (std.mem.indexOf(u8, pattern, ":")) |_| {
            return self.parameterMatches(pattern, path);
        }
        
        return false;
    }
    
    fn parameterMatches(self: *Self, pattern: []const u8, path: []const u8) bool {
        _ = self;
        
        var pattern_parts = std.mem.split(u8, pattern, "/");
        var path_parts = std.mem.split(u8, path, "/");
        
        while (pattern_parts.next()) |pattern_part| {
            const path_part = path_parts.next() orelse return false;
            
            if (pattern_part.len > 0 and pattern_part[0] == ':') {
                // Parameter segment - matches any non-empty path segment
                if (path_part.len == 0) return false;
            } else {
                // Literal segment - must match exactly
                if (!std.mem.eql(u8, pattern_part, path_part)) {
                    return false;
                }
            }
        }
        
        // Ensure no extra path segments
        return path_parts.next() == null;
    }
    
    fn extractParams(self: *Self, route: *const Route, request: *const RoutingRequest) !?std.StringHashMap([]const u8) {
        var params = std.StringHashMap([]const u8).init(self.allocator);
        
        if (std.mem.indexOf(u8, route.path, ":") == null) {
            return null; // No parameters to extract
        }
        
        var pattern_parts = std.mem.split(u8, route.path, "/");
        var path_parts = std.mem.split(u8, request.path, "/");
        
        while (pattern_parts.next()) |pattern_part| {
            const path_part = path_parts.next() orelse break;
            
            if (pattern_part.len > 0 and pattern_part[0] == ':') {
                const param_name = pattern_part[1..];
                try params.put(try self.allocator.dupe(u8, param_name), try self.allocator.dupe(u8, path_part));
            }
        }
        
        return params;
    }
    
    pub fn addMiddleware(self: *Self, middleware: Middleware) !void {
        try self.middleware.append(middleware);
    }
};

pub const HttpMethod = enum {
    GET,
    POST,
    PUT,
    DELETE,
    HEAD,
    OPTIONS,
    PATCH,
    ANY,
};

pub const RouteType = enum {
    static,      // Serve static files
    proxy,       // Reverse proxy to backend
    redirect,    // HTTP redirect
    api,         // API endpoint
    websocket,   // WebSocket upgrade
};

pub const RouteConfig = struct {
    path: []const u8,
    host: ?[]const u8 = null,
    method: HttpMethod = .ANY,
    handler: RouteHandler,
    route_type: RouteType = .api,
    priority: u8 = 50, // 0-255, higher = higher priority
    middleware: []const Middleware = &.{},
};

pub const Route = struct {
    path: []const u8,
    host: ?[]const u8,
    method: HttpMethod,
    handler: RouteHandler,
    route_type: RouteType,
    priority: u8,
    middleware: []const Middleware,
};

pub const RoutingRequest = struct {
    path: []const u8,
    host: ?[]const u8,
    method: HttpMethod,
    headers: std.StringHashMap([]const u8),
    remote_addr: ?[]const u8,
};

pub const RouteMatch = struct {
    route: *const Route,
    params: ?std.StringHashMap([]const u8),
};

pub const RouteHandler = *const fn (request: *const RoutingRequest, params: ?std.StringHashMap([]const u8)) anyerror!RouteResponse;

pub const RouteResponse = struct {
    status: u16,
    body: []const u8,
    headers: std.StringHashMap([]const u8),
    content_type: []const u8 = "text/html",
};

pub const Middleware = struct {
    name: []const u8,
    handler: MiddlewareHandler,
};

pub const MiddlewareHandler = *const fn (request: *RoutingRequest, next: *const fn() anyerror!RouteResponse) anyerror!RouteResponse;

/// Create a basic router with common routes
pub fn createDefaultRouter(allocator: Allocator) !Router {
    var router = Router.init(allocator);
    
    // Add health check endpoint
    try router.addRoute(.{
        .path = "/health",
        .method = .GET,
        .handler = healthCheckHandler,
        .priority = 100,
    });
    
    // Add status endpoint
    try router.addRoute(.{
        .path = "/status",
        .method = .GET,
        .handler = statusHandler,
        .priority = 100,
    });
    
    // Add catch-all for static files
    try router.addRoute(.{
        .path = "/*",
        .method = .GET,
        .handler = staticFileHandler,
        .route_type = .static,
        .priority = 1, // Lowest priority
    });
    
    return router;
}

fn healthCheckHandler(request: *const RoutingRequest, params: ?std.StringHashMap([]const u8)) !RouteResponse {
    _ = request;
    _ = params;
    
    var headers = std.StringHashMap([]const u8).init(std.heap.page_allocator);
    try headers.put("content-type", "application/json");
    
    return RouteResponse{
        .status = 200,
        .body = "{\"status\":\"ok\",\"protocol\":\"HTTP/3\",\"transport\":\"QUIC\"}",
        .headers = headers,
        .content_type = "application/json",
    };
}

fn statusHandler(request: *const RoutingRequest, params: ?std.StringHashMap([]const u8)) !RouteResponse {
    _ = request;
    _ = params;
    
    var headers = std.StringHashMap([]const u8).init(std.heap.page_allocator);
    try headers.put("content-type", "application/json");
    
    const status_json = 
        \\{
        \\  "server": "Wraith HTTP/3 Proxy",
        \\  "version": "0.1.0",
        \\  "protocol": "HTTP/3",
        \\  "transport": "QUIC",
        \\  "tls": "1.3",
        \\  "uptime": "unknown"
        \\}
    ;
    
    return RouteResponse{
        .status = 200,
        .body = status_json,
        .headers = headers,
        .content_type = "application/json",
    };
}

fn staticFileHandler(request: *const RoutingRequest, params: ?std.StringHashMap([]const u8)) !RouteResponse {
    _ = params;
    
    var headers = std.StringHashMap([]const u8).init(std.heap.page_allocator);
    try headers.put("content-type", "text/html");
    
    // Simple static response for now
    const html = 
        \\<!DOCTYPE html>
        \\<html>
        \\<head><title>🔥 Wraith HTTP/3 Server</title></head>
        \\<body>
        \\<h1>🔥 Welcome to Wraith!</h1>
        \\<p>🚀 Modern QUIC/HTTP3 Reverse Proxy</p>
        \\<p>✅ Protocol: HTTP/3 over QUIC</p>
        \\<p>🔒 TLS: 1.3 (post-quantum ready)</p>
        \\<p>⚡ Transport: UDP (no TCP dependency)</p>
        \\<p>🎯 Built with Zig for maximum performance</p>
        \\<p>📍 Requested path: {s}</p>
        \\</body>
        \\</html>
    ;
    
    const body = try std.fmt.allocPrint(std.heap.page_allocator, html, .{request.path});
    
    return RouteResponse{
        .status = 200,
        .body = body,
        .headers = headers,
        .content_type = "text/html",
    };
}
