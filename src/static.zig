//! Advanced Static File Server for Wraith
//! Serves static files with compression, caching, and security features

const std = @import("std");
const root = @import("root.zig");
const zcrypto = root.zcrypto;

const Allocator = std.mem.Allocator;

pub const StaticFileServer = struct {
    allocator: Allocator,
    config: StaticConfig,
    file_cache: std.StringHashMap(CachedFile),
    etag_cache: std.StringHashMap([]const u8),
    mime_types: std.StringHashMap([]const u8),
    
    const Self = @This();
    
    pub fn init(allocator: Allocator, config: StaticConfig) !Self {
        var server = Self{
            .allocator = allocator,
            .config = config,
            .file_cache = std.StringHashMap(CachedFile).init(allocator),
            .etag_cache = std.StringHashMap([]const u8).init(allocator),
            .mime_types = std.StringHashMap([]const u8).init(allocator),
        };
        
        try server.initializeMimeTypes();
        return server;
    }
    
    pub fn deinit(self: *Self) void {
        // Clean up file cache
        var cache_iter = self.file_cache.iterator();
        while (cache_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.file_cache.deinit();
        
        // Clean up ETag cache
        var etag_iter = self.etag_cache.iterator();
        while (etag_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.etag_cache.deinit();
        
        // Clean up MIME types
        var mime_iter = self.mime_types.iterator();
        while (mime_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.mime_types.deinit();
    }
    
    pub fn serveFile(self: *Self, request_path: []const u8, headers: std.StringHashMap([]const u8)) !StaticResponse {
        if (!self.config.enabled) {
            return StaticResponse{
                .status = 404,
                .body = "Static file serving disabled",
                .headers = std.StringHashMap([]const u8).init(self.allocator),
                .content_type = "text/plain",
            };
        }
        
        // Sanitize path to prevent directory traversal
        const safe_path = try self.sanitizePath(request_path);
        defer self.allocator.free(safe_path);
        
        // Build full file path
        const full_path = try std.fs.path.join(self.allocator, &.{ self.config.root, safe_path });
        defer self.allocator.free(full_path);
        
        // Check if file exists and get info
        const file_info = std.fs.cwd().statFile(full_path) catch |err| switch (err) {
            error.FileNotFound => {
                // Try index files if path is a directory
                if (std.mem.endsWith(u8, safe_path, "/") or safe_path.len == 0) {
                    return self.tryIndexFiles(full_path, headers);
                }
                return self.notFoundResponse();
            },
            else => return err,
        };
        
        // Don't serve directories directly
        if (file_info.kind == .directory) {
            return self.tryIndexFiles(full_path, headers);
        }
        
        // Check if-modified-since header
        if (headers.get("if-modified-since")) |ims| {
            if (self.isNotModified(file_info.mtime, ims)) {
                return self.notModifiedResponse(full_path);
            }
        }
        
        // Check ETag
        if (headers.get("if-none-match")) |etag| {
            const file_etag = try self.generateETag(full_path, file_info);
            if (std.mem.eql(u8, etag, file_etag)) {
                return self.notModifiedResponse(full_path);
            }
        }
        
        // Load and serve file
        return self.loadAndServeFile(full_path, file_info);
    }
    
    fn sanitizePath(self: *Self, path: []const u8) ![]const u8 {
        var normalized = std.ArrayList(u8).init(self.allocator);
        defer normalized.deinit();
        
        // Remove leading slash and normalize
        const clean_path = if (path.len > 0 and path[0] == '/') path[1..] else path;
        
        var parts = std.mem.split(u8, clean_path, "/");
        var path_parts = std.ArrayList([]const u8).init(self.allocator);
        defer path_parts.deinit();
        
        while (parts.next()) |part| {
            if (part.len == 0 or std.mem.eql(u8, part, ".")) {
                continue;
            }
            if (std.mem.eql(u8, part, "..")) {
                if (path_parts.items.len > 0) {
                    _ = path_parts.pop();
                }
                continue;
            }
            
            // Check for dangerous characters
            for (part) |char| {
                if (char < 32 or char == 127) {
                    return error.InvalidPath;
                }
            }
            
            try path_parts.append(part);
        }
        
        // Rebuild path
        for (path_parts.items, 0..) |part, i| {
            if (i > 0) try normalized.append('/');
            try normalized.appendSlice(part);
        }
        
        return normalized.toOwnedSlice();
    }
    
    fn tryIndexFiles(self: *Self, dir_path: []const u8, headers: std.StringHashMap([]const u8)) !StaticResponse {
        for (self.config.index_files) |index_file| {
            const index_path = try std.fs.path.join(self.allocator, &.{ dir_path, index_file });
            defer self.allocator.free(index_path);
            
            const file_info = std.fs.cwd().statFile(index_path) catch continue;
            
            if (file_info.kind == .file) {
                return self.loadAndServeFile(index_path, file_info);
            }
        }
        
        // If autoindex is enabled, generate directory listing
        if (self.config.autoindex) {
            return self.generateDirectoryListing(dir_path);
        }
        
        _ = headers;
        return self.notFoundResponse();
    }
    
    fn loadAndServeFile(self: *Self, file_path: []const u8, file_info: std.fs.File.Stat) !StaticResponse {
        // Check cache first
        if (self.file_cache.get(file_path)) |cached| {
            if (cached.mtime == file_info.mtime and cached.size == file_info.size) {
                std.log.debug("Serving cached file: {s}", .{file_path});
                return self.createResponseFromCache(cached, file_path);
            }
        }
        
        // Read file
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();
        
        const file_content = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        
        // Determine content type
        const content_type = self.getContentType(file_path);
        
        // Generate ETag
        const etag = try self.generateETag(file_path, file_info);
        
        // Compress if enabled and content type is compressible
        var body = file_content;
        var compressed = false;
        
        if (self.config.compression and self.isCompressible(content_type)) {
            if (self.compressContent(file_content)) |compressed_content| {
                self.allocator.free(file_content);
                body = compressed_content;
                compressed = true;
            } else |_| {
                // Compression failed, use original content
            }
        }
        
        // Cache the file
        try self.cacheFile(file_path, CachedFile{
            .content = try self.allocator.dupe(u8, body),
            .content_type = try self.allocator.dupe(u8, content_type),
            .etag = try self.allocator.dupe(u8, etag),
            .mtime = file_info.mtime,
            .size = file_info.size,
            .compressed = compressed,
        });
        
        return self.createResponse(body, content_type, etag, compressed);
    }
    
    fn createResponse(self: *Self, body: []const u8, content_type: []const u8, etag: []const u8, compressed: bool) !StaticResponse {
        var headers = std.StringHashMap([]const u8).init(self.allocator);
        
        // Add standard headers
        try headers.put(try self.allocator.dupe(u8, "content-type"), try self.allocator.dupe(u8, content_type));
        try headers.put(try self.allocator.dupe(u8, "etag"), try self.allocator.dupe(u8, etag));
        
        if (self.config.cache_control) |cache_control| {
            try headers.put(try self.allocator.dupe(u8, "cache-control"), try self.allocator.dupe(u8, cache_control));
        }
        
        if (compressed) {
            try headers.put(try self.allocator.dupe(u8, "content-encoding"), try self.allocator.dupe(u8, "gzip"));
        }
        
        // Add security headers
        try headers.put(try self.allocator.dupe(u8, "x-content-type-options"), try self.allocator.dupe(u8, "nosniff"));
        try headers.put(try self.allocator.dupe(u8, "x-frame-options"), try self.allocator.dupe(u8, "DENY"));
        
        return StaticResponse{
            .status = 200,
            .body = try self.allocator.dupe(u8, body),
            .headers = headers,
            .content_type = content_type,
        };
    }
    
    fn createResponseFromCache(self: *Self, cached: CachedFile, file_path: []const u8) !StaticResponse {
        _ = file_path;
        return self.createResponse(cached.content, cached.content_type, cached.etag, cached.compressed);
    }
    
    fn generateETag(self: *Self, file_path: []const u8, file_info: std.fs.File.Stat) ![]const u8 {
        if (self.etag_cache.get(file_path)) |cached_etag| {
            return cached_etag;
        }
        
        // Generate ETag from file path, size, and mtime using zcrypto
        var hasher = zcrypto.hash.sha256.Sha256.init();
        hasher.update(file_path);
        hasher.update(std.mem.asBytes(&file_info.size));
        hasher.update(std.mem.asBytes(&file_info.mtime));
        
        var hash: [32]u8 = undefined;
        hasher.final(&hash);
        
        // Convert to hex string
        var etag_buffer: [64]u8 = undefined;
        _ = std.fmt.bufPrint(&etag_buffer, "{}", .{std.fmt.fmtSliceHexLower(&hash)}) catch unreachable;
        
        const etag = try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{etag_buffer});
        
        // Cache the ETag
        try self.etag_cache.put(try self.allocator.dupe(u8, file_path), etag);
        
        return etag;
    }
    
    fn getContentType(self: *Self, file_path: []const u8) []const u8 {
        const ext = std.fs.path.extension(file_path);
        return self.mime_types.get(ext) orelse "application/octet-stream";
    }
    
    fn isCompressible(self: *Self, content_type: []const u8) bool {
        for (self.config.compression_types) |compressible_type| {
            if (std.mem.startsWith(u8, content_type, compressible_type)) {
                return true;
            }
        }
        return false;
    }
    
    fn compressContent(self: *Self, content: []const u8) ![]const u8 {
        // Simple gzip compression using std.compress.gzip
        var compressed = std.ArrayList(u8).init(self.allocator);
        var compressor = try std.compress.gzip.compressor(compressed.writer(), .{});
        
        try compressor.writer().writeAll(content);
        try compressor.close();
        
        return compressed.toOwnedSlice();
    }
    
    fn cacheFile(self: *Self, file_path: []const u8, cached_file: CachedFile) !void {
        const key = try self.allocator.dupe(u8, file_path);
        try self.file_cache.put(key, cached_file);
    }
    
    fn isNotModified(self: *Self, file_mtime: i128, ims_header: []const u8) bool {
        _ = self;
        _ = file_mtime;
        _ = ims_header;
        // Simplified: In a real implementation, parse the date and compare
        return false;
    }
    
    fn notModifiedResponse(self: *Self, file_path: []const u8) !StaticResponse {
        var headers = std.StringHashMap([]const u8).init(self.allocator);
        
        if (self.etag_cache.get(file_path)) |etag| {
            try headers.put(try self.allocator.dupe(u8, "etag"), try self.allocator.dupe(u8, etag));
        }
        
        return StaticResponse{
            .status = 304,
            .body = "",
            .headers = headers,
            .content_type = "",
        };
    }
    
    fn notFoundResponse(self: *Self) !StaticResponse {
        var headers = std.StringHashMap([]const u8).init(self.allocator);
        try headers.put(try self.allocator.dupe(u8, "content-type"), try self.allocator.dupe(u8, "text/html"));
        
        const body = 
            \\<!DOCTYPE html>
            \\<html>
            \\<head><title>404 Not Found</title></head>
            \\<body>
            \\<h1>404 Not Found</h1>
            \\<p>The requested file was not found on this server.</p>
            \\<hr>
            \\<p><em>Wraith HTTP/3 Server</em></p>
            \\</body>
            \\</html>
        ;
        
        return StaticResponse{
            .status = 404,
            .body = try self.allocator.dupe(u8, body),
            .headers = headers,
            .content_type = "text/html",
        };
    }
    
    fn generateDirectoryListing(self: *Self, dir_path: []const u8) !StaticResponse {
        var html = std.ArrayList(u8).init(self.allocator);
        defer html.deinit();
        
        try html.appendSlice("<!DOCTYPE html><html><head><title>Directory Listing</title></head><body>");
        try html.appendSlice("<h1>Directory Listing</h1><ul>");
        
        var dir = std.fs.cwd().openIterableDir(dir_path, .{}) catch {
            return self.notFoundResponse();
        };
        defer dir.close();
        
        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            try html.writer().print("<li><a href=\"{s}\">{s}</a></li>", .{ entry.name, entry.name });
        }
        
        try html.appendSlice("</ul></body></html>");
        
        var headers = std.StringHashMap([]const u8).init(self.allocator);
        try headers.put(try self.allocator.dupe(u8, "content-type"), try self.allocator.dupe(u8, "text/html"));
        
        return StaticResponse{
            .status = 200,
            .body = try html.toOwnedSlice(),
            .headers = headers,
            .content_type = "text/html",
        };
    }
    
    fn initializeMimeTypes(self: *Self) !void {
        const mime_map = [_]struct { ext: []const u8, mime: []const u8 }{
            .{ .ext = ".html", .mime = "text/html; charset=utf-8" },
            .{ .ext = ".htm", .mime = "text/html; charset=utf-8" },
            .{ .ext = ".css", .mime = "text/css" },
            .{ .ext = ".js", .mime = "application/javascript" },
            .{ .ext = ".json", .mime = "application/json" },
            .{ .ext = ".xml", .mime = "application/xml" },
            .{ .ext = ".png", .mime = "image/png" },
            .{ .ext = ".jpg", .mime = "image/jpeg" },
            .{ .ext = ".jpeg", .mime = "image/jpeg" },
            .{ .ext = ".gif", .mime = "image/gif" },
            .{ .ext = ".svg", .mime = "image/svg+xml" },
            .{ .ext = ".ico", .mime = "image/x-icon" },
            .{ .ext = ".pdf", .mime = "application/pdf" },
            .{ .ext = ".txt", .mime = "text/plain" },
            .{ .ext = ".woff", .mime = "font/woff" },
            .{ .ext = ".woff2", .mime = "font/woff2" },
            .{ .ext = ".ttf", .mime = "font/ttf" },
            .{ .ext = ".otf", .mime = "font/otf" },
        };
        
        for (mime_map) |entry| {
            try self.mime_types.put(
                try self.allocator.dupe(u8, entry.ext),
                try self.allocator.dupe(u8, entry.mime)
            );
        }
    }
    
    pub fn clearCache(self: *Self) void {
        var cache_iter = self.file_cache.iterator();
        while (cache_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.file_cache.clearAndFree();
        
        var etag_iter = self.etag_cache.iterator();
        while (etag_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.etag_cache.clearAndFree();
    }
    
    pub fn getStats(self: *Self) StaticServerStats {
        return StaticServerStats{
            .cached_files = @intCast(self.file_cache.count()),
            .cache_memory_usage = self.calculateCacheSize(),
        };
    }
    
    fn calculateCacheSize(self: *Self) u64 {
        var total_size: u64 = 0;
        var cache_iter = self.file_cache.iterator();
        while (cache_iter.next()) |entry| {
            total_size += entry.value_ptr.content.len;
        }
        return total_size;
    }
};

pub const StaticConfig = struct {
    enabled: bool = true,
    root: []const u8 = "./public",
    index_files: []const []const u8 = &.{ "index.html", "index.htm" },
    compression: bool = true,
    compression_types: []const []const u8 = &.{
        "text/html", "text/css", "application/javascript", 
        "application/json", "text/plain", "image/svg+xml"
    },
    cache_control: ?[]const u8 = "public, max-age=3600",
    etag: bool = true,
    autoindex: bool = false,
    max_file_size: u64 = 50 * 1024 * 1024, // 50MB
};

pub const CachedFile = struct {
    content: []const u8,
    content_type: []const u8,
    etag: []const u8,
    mtime: i128,
    size: u64,
    compressed: bool,
    
    pub fn deinit(self: *const CachedFile, allocator: Allocator) void {
        allocator.free(self.content);
        allocator.free(self.content_type);
        allocator.free(self.etag);
    }
};

pub const StaticResponse = struct {
    status: u16,
    body: []const u8,
    headers: std.StringHashMap([]const u8),
    content_type: []const u8,
};

pub const StaticServerStats = struct {
    cached_files: u32,
    cache_memory_usage: u64, // bytes
};
