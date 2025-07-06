//! Wraith Server - Core HTTP/3 + QUIC Server Implementation
//! Phase 1: HTTP/3 with QUIC transport and TLS 1.3

const std = @import("std");
const root = @import("root.zig");
const zquic = root.zquic;
const tokioZ = root.tokioZ;
const crypto = root.crypto_interface;

const print = std.debug.print;
const Allocator = std.mem.Allocator;

pub const ServerConfig = struct {
    bind_address: []const u8 = "::1", // IPv6 first
    port: u16 = 443,
    cert_path: []const u8 = "certs/server.crt",
    key_path: []const u8 = "certs/server.key",
    static_root: []const u8 = "./public",
    max_connections: u32 = 10000,
    enable_compression: bool = true,
    enable_http3: bool = true,
    enable_tls13_only: bool = true,
};

pub const WraithServer = struct {
    allocator: Allocator,
    config: ServerConfig,
    runtime: tokioZ.AsyncRuntime,
    quic_server: ?zquic.Http3.Http3Server,
    tls_configured: bool = false,
    is_running: bool = false,

    const Self = @This();

    pub fn init(allocator: Allocator, config: ServerConfig) !Self {
        print("🔧 Initializing Wraith server with QUIC/HTTP3...\n", .{});
        
        // Initialize zquic library
        try zquic.init(allocator);
        
        // Create async runtime optimized for I/O (perfect for QUIC!)
        const runtime = try tokioZ.AsyncRuntime.init(allocator);
        
        // TLS will be configured using injected crypto primitives when needed
        
        return Self{
            .allocator = allocator,
            .config = config,
            .runtime = runtime,
            .quic_server = null,
            .tls_configured = false,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.quic_server) |*server| {
            server.deinit();
        }
        self.runtime.deinit();
        zquic.deinit();
    }

    pub fn start(self: *Self) !void {
        print("🚀 Starting Wraith HTTP/3 server on {s}:{}\n", .{ self.config.bind_address, self.config.port });
        
        // Create QUIC server config compatible with zquic v0.4.0
        const quic_config = zquic.Http3.ServerConfig{
            .max_connections = self.config.max_connections,
            .enable_compression = self.config.enable_compression,
            .static_files_root = self.config.static_root,
            .enable_security_headers = true,
        };
        
        // Create QUIC server with proper config
        self.quic_server = try zquic.Http3.Http3Server.init(self.allocator, quic_config);

        self.is_running = true;
        
        // Run the server directly (avoiding TokioZ bug)
        try self.runServer();
    }

    fn runServer(self: *Self) !void {
        var server = &self.quic_server.?;
        
        print("✅ Wraith ready! HTTP/3 server initialized\n", .{});
        print("📋 Server features:\n", .{});
        print("   • Protocol: HTTP/3 over QUIC (zquic v0.4.0)\n", .{});
        print("   • Libraries: zquic, zcrypto, tokioZ\n", .{});
        print("   • Max connections: {}\n", .{self.config.max_connections});

        // Add some basic routes for demonstration
        try server.get("/", handleIndex);
        try server.get("/health", handleHealth);
        try server.get("/stats", handleStats);
        
        // Start the HTTP/3 server
        try server.start();
        
        print("🎉 Wraith HTTP/3 server started successfully!\n", .{});
        print("🌐 Ready to handle HTTP/3 requests on {s}:{}\n", .{ self.config.bind_address, self.config.port });
        
        // Keep the server running
        while (self.is_running) {
            std.time.sleep(1000 * 1000 * 1000); // Sleep 1 second
            server.cleanupExpiredConnections();
        }
    }

    fn handleConnection(self: *Self, connection: zquic.Connection) !void {
        print("🔗 New QUIC connection established\n", .{});
        defer print("🔌 QUIC connection closed\n", .{});
        
        while (connection.isAlive()) {
            // Handle HTTP/3 streams
            if (try connection.acceptStream()) |stream| {
                _ = try self.runtime.spawn(self.handleHttp3Stream(stream));
            }
            
            // Small yield to prevent busy waiting
            try tokioZ.sleep(1); // 1ms
        }
    }

    fn handleHttp3Stream(self: *Self, stream: zquic.Stream) !void {
        defer stream.close();
        
        // Parse HTTP/3 request
        const request = try self.parseHttp3Request(stream);
        defer request.deinit(self.allocator);
        
        print("📨 HTTP/3 Request: {} {s}\n", .{ request.method, request.path });
        
        // Route the request
        const response = try self.routeRequest(request);
        defer response.deinit(self.allocator);
        
        // Send HTTP/3 response
        try self.sendHttp3Response(stream, response);
    }

    const Http3Request = struct {
        method: std.http.Method,
        path: []const u8,
        headers: std.StringHashMap([]const u8),
        body: []const u8,
        
        pub fn deinit(self: *const Http3Request, allocator: Allocator) void {
            allocator.free(self.path);
            allocator.free(self.body);
            var iter = self.headers.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
        }
    };

    const Http3Response = struct {
        status: u16,
        headers: std.StringHashMap([]const u8),
        body: []const u8,
        
        pub fn deinit(self: *const Http3Response, allocator: Allocator) void {
            allocator.free(self.body);
            var iter = self.headers.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
        }
    };

    fn parseHttp3Request(self: *Self, stream: zquic.Stream) !Http3Request {
        // This is a simplified HTTP/3 request parser
        // In reality, this would parse QPACK headers and HTTP/3 frames
        
        const headers = std.StringHashMap([]const u8).init(self.allocator);
        
        // Read HTTP/3 frames from stream
        const frame_data = try stream.readFrame(self.allocator);
        defer self.allocator.free(frame_data);
        
        // Parse HEADERS frame (simplified)
        // TODO: Implement proper QPACK decompression
        const method = std.http.Method.GET; // Default for now
        const path = try self.allocator.dupe(u8, "/"); // Default path
        const body = try self.allocator.alloc(u8, 0); // Empty body for now
        
        return Http3Request{
            .method = method,
            .path = path,
            .headers = headers,
            .body = body,
        };
    }

    fn routeRequest(self: *Self, request: Http3Request) !Http3Response {
        var headers = std.StringHashMap([]const u8).init(self.allocator);
        
        // Add standard HTTP/3 headers
        try headers.put(try self.allocator.dupe(u8, "server"), try self.allocator.dupe(u8, "Wraith/0.1.0"));
        try headers.put(try self.allocator.dupe(u8, "content-type"), try self.allocator.dupe(u8, "text/html; charset=utf-8"));
        
        // Simple routing logic
        if (std.mem.eql(u8, request.path, "/")) {
            const body = 
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
                \\</body>
                \\</html>
            ;
            
            return Http3Response{
                .status = 200,
                .headers = headers,
                .body = try self.allocator.dupe(u8, body),
            };
        } else if (std.mem.eql(u8, request.path, "/health")) {
            const body = "{\"status\":\"ok\",\"protocol\":\"HTTP/3\",\"transport\":\"QUIC\"}";
            try headers.put(try self.allocator.dupe(u8, "content-type"), try self.allocator.dupe(u8, "application/json"));
            
            return Http3Response{
                .status = 200,
                .headers = headers,
                .body = try self.allocator.dupe(u8, body),
            };
        } else {
            // 404 Not Found
            const body = "<!DOCTYPE html><html><head><title>404 Not Found</title></head><body><h1>404 Not Found</h1><p>The requested resource was not found on this server.</p></body></html>";
            
            return Http3Response{
                .status = 404,
                .headers = headers,
                .body = try self.allocator.dupe(u8, body),
            };
        }
    }

    fn sendHttp3Response(_: *Self, stream: zquic.Stream, response: Http3Response) !void {
        // Send HTTP/3 HEADERS frame with status and headers
        try stream.sendHeaders(response.status, response.headers);
        
        // Send HTTP/3 DATA frame with body
        if (response.body.len > 0) {
            try stream.sendData(response.body);
        }
        
        // Send end-of-stream
        try stream.finish();
        
        print("📤 HTTP/3 Response sent: {} ({} bytes)\n", .{ response.status, response.body.len });
    }

    pub fn stop(self: *Self) void {
        print("🛑 Stopping Wraith server...\n", .{});
        self.is_running = false;
    }
};

/// Request handlers for HTTP/3 routes
fn handleIndex(req: *zquic.Http3.Request, res: *zquic.Http3.Response) !void {
    _ = req;
    try res.json(.{
        .message = "🔥 Wraith HTTP/3 Proxy Server",
        .version = "0.2.0",
        .protocol = "HTTP/3 over QUIC",
        .status = "running"
    });
}

fn handleHealth(req: *zquic.Http3.Request, res: *zquic.Http3.Response) !void {
    _ = req;
    try res.json(.{
        .status = "healthy",
        .protocol = "HTTP/3",
        .uptime = std.time.timestamp()
    });
}

fn handleStats(req: *zquic.Http3.Request, res: *zquic.Http3.Response) !void {
    _ = req;
    // In a real implementation, we'd get actual stats from the server
    try res.json(.{
        .connections = 0,
        .requests_processed = 0,
        .bytes_sent = 0,
        .bytes_received = 0
    });
}

/// Start the Wraith server with default configuration
pub fn start(allocator: Allocator) !void {
    const config = ServerConfig{};
    var server = try WraithServer.init(allocator, config);
    defer server.deinit();
    
    try server.start();
}

/// Start the Wraith server with custom configuration
pub fn startWithConfig(allocator: Allocator, config: ServerConfig) !void {
    var server = try WraithServer.init(allocator, config);
    defer server.deinit();
    
    try server.start();
}
