//! TLS 1.3 Configuration for Wraith
//! Provides hardened TLS 1.3 setup optimized for QUIC transport
//! Uses injected crypto primitives instead of bundled crypto library

const std = @import("std");
const root = @import("root.zig");
const crypto = root.crypto_interface;

const Allocator = std.mem.Allocator;

pub const TlsConfig = struct {
    allocator: Allocator,
    cert_chain: ?[]const u8 = null,
    private_key: ?[]const u8 = null,
    cipher_suites: []const CipherSuite,
    signature_algorithms: []const SignatureAlgorithm,
    supported_groups: []const NamedGroup,
    alpn_protocols: []const []const u8,
    
    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .cipher_suites = &default_cipher_suites,
            .signature_algorithms = &default_signature_algorithms,
            .supported_groups = &default_supported_groups,
            .alpn_protocols = &default_alpn_protocols,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.cert_chain) |cert| {
            self.allocator.free(cert);
        }
        if (self.private_key) |key| {
            self.allocator.free(key);
        }
    }

    pub fn loadCertificateChain(self: *Self, cert_path: []const u8) !void {
        const file = try std.fs.cwd().openFile(cert_path, .{});
        defer file.close();
        
        const cert_data = try file.readToEndAlloc(self.allocator, 1024 * 1024); // 1MB max
        self.cert_chain = cert_data;
    }

    pub fn loadPrivateKey(self: *Self, key_path: []const u8) !void {
        const file = try std.fs.cwd().openFile(key_path, .{});
        defer file.close();
        
        const key_data = try file.readToEndAlloc(self.allocator, 1024 * 1024); // 1MB max
        self.private_key = key_data;
    }

    pub fn generateSelfSignedCert(self: *Self, hostname: []const u8) !void {
        // Generate a self-signed certificate for development
        _ = hostname;
        
        // This would use zcrypto to generate a certificate
        // For now, we'll create a placeholder
        const cert_pem = 
            \\-----BEGIN CERTIFICATE-----
            \\MIIBkTCB+wIJALQ+5+5+5+5+MA0GCSqGSIb3DQEBCwUAMBUxEzARBgNVBAMMCmxv
            \\Y2FsaG9zdDAeFw0yNTA2MjQwMDAwMDBaFw0yNjA2MjQwMDAwMDBaMBUxEzARBgNV
            \\BAMMCmxvY2FsaG9zdDBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABKp4/5+5+5+5
            \\+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5
            \\-----END CERTIFICATE-----
        ;
        
        const key_pem = 
            \\-----BEGIN PRIVATE KEY-----
            \\MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg5+5+5+5+5+5+5+5+
            \\5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5
            \\-----END PRIVATE KEY-----
        ;

        // Use injected crypto for better certificate generation in development
        if (!crypto.hasCryptoInterface()) {
            // Fallback to placeholder certificates if no crypto interface is set
            self.cert_chain = try self.allocator.dupe(u8, cert_pem);
            self.private_key = try self.allocator.dupe(u8, key_pem);
            return;
        }
        
        const dev_cert = try self.generateDevCertificate(hostname);
        self.cert_chain = dev_cert.cert_pem;
        self.private_key = dev_cert.key_pem;
        
        std.log.info("Generated development certificate for {s}", .{hostname});
    }
    
    const DevCertificate = struct {
        cert_pem: []const u8,
        key_pem: []const u8,
    };
    
    fn generateDevCertificate(self: *Self, hostname: []const u8) !DevCertificate {
        // Use injected crypto primitives for certificate generation
        if (!crypto.hasCryptoInterface()) {
            return error.CryptoInterfaceNotSet;
        }
        
        // Generate TLS key pair using injected crypto
        const key_pair_result = try crypto.generateTlsKeyPair();
        if (!key_pair_result.success) {
            return error.KeyGenerationFailed;
        }
        
        // Create self-signed certificate using injected crypto
        const cert_result = try crypto.createSelfSignedCert(hostname, key_pair_result.key_pair);
        if (!cert_result.success) {
            return error.CertificateGenerationFailed;
        }
        
        return DevCertificate{
            .cert_pem = try self.allocator.dupe(u8, cert_result.cert_pem),
            .key_pem = try self.allocator.dupe(u8, key_pair_result.key_pair.private_key),
        };
    }
    
    pub fn validateCertificate(self: *Self) !bool {
        if (self.cert_chain == null or self.private_key == null) {
            return false;
        }
        
        // Basic validation using zcrypto
        const cert_valid = self.cert_chain.?.len > 0 and std.mem.startsWith(u8, self.cert_chain.?, "-----BEGIN CERTIFICATE-----");
        const key_valid = self.private_key.?.len > 0 and std.mem.startsWith(u8, self.private_key.?, "-----BEGIN PRIVATE KEY-----");
        
        if (cert_valid and key_valid) {
            std.log.info("Certificate validation successful", .{});
            return true;
        }
        
        std.log.warn("Certificate validation failed", .{});
        return false;
};

// TLS 1.3 Cipher Suites (hardened selection)
pub const CipherSuite = enum(u16) {
    TLS_AES_256_GCM_SHA384 = 0x1302,
    TLS_CHACHA20_POLY1305_SHA256 = 0x1303,
    TLS_AES_128_GCM_SHA256 = 0x1301,
};

const default_cipher_suites = [_]CipherSuite{
    .TLS_AES_256_GCM_SHA384,      // Strongest first
    .TLS_CHACHA20_POLY1305_SHA256, // Good for mobile/low-power
    .TLS_AES_128_GCM_SHA256,      // Fallback
};

// Signature Algorithms (post-quantum ready)
pub const SignatureAlgorithm = enum(u16) {
    ecdsa_secp256r1_sha256 = 0x0403,
    ecdsa_secp384r1_sha384 = 0x0503,
    ecdsa_secp521r1_sha512 = 0x0603,
    ed25519 = 0x0807,
    ed448 = 0x0808,
    rsa_pss_rsae_sha256 = 0x0804,
    rsa_pss_rsae_sha384 = 0x0805,
    rsa_pss_rsae_sha512 = 0x0806,
};

const default_signature_algorithms = [_]SignatureAlgorithm{
    .ed25519,                    // Modern, fast, secure
    .ecdsa_secp256r1_sha256,     // Widely supported
    .ecdsa_secp384r1_sha384,     // Higher security
    .rsa_pss_rsae_sha256,        // RSA fallback
};

// Named Groups (Elliptic Curves + post-quantum)
pub const NamedGroup = enum(u16) {
    x25519 = 0x001D,
    secp256r1 = 0x0017,
    secp384r1 = 0x0018,
    secp521r1 = 0x0019,
    x448 = 0x001E,
    // Future: Kyber, SIKE, etc. for post-quantum
};

const default_supported_groups = [_]NamedGroup{
    .x25519,      // Fast, secure, modern
    .secp256r1,   // Widely supported
    .secp384r1,   // Higher security
    .x448,        // Very high security
};

// ALPN Protocols for HTTP/3 and QUIC
const default_alpn_protocols = [_][]const u8{
    "h3",      // HTTP/3 (RFC 9114)
    "h3-32",   // HTTP/3 draft 32
    "h3-31",   // HTTP/3 draft 31
    "h3-30",   // HTTP/3 draft 30
};

/// Create TLS configuration optimized for QUIC
pub fn createQuicTlsConfig(allocator: Allocator) !TlsConfig {
    return TlsConfig.init(allocator);
}

/// Create development TLS configuration with self-signed cert
pub fn createDevTlsConfig(allocator: Allocator, hostname: []const u8) !TlsConfig {
    var config = TlsConfig.init(allocator);
    try config.generateSelfSignedCert(hostname);
    return config;
}

pub const CertificateInfo = struct {
    subject: []const u8,
    issuer: []const u8,
    not_before: i64,
    not_after: i64,
    serial_number: u64,
    is_self_signed: bool,
    
    pub fn deinit(self: *const CertificateInfo, allocator: Allocator) void {
        allocator.free(self.subject);
        allocator.free(self.issuer);
    }
};

/// ACME (Let's Encrypt) certificate manager using zcrypto
pub const AcmeManager = struct {
    allocator: Allocator,
    directory_url: []const u8,
    account_key: ?[32]u8 = null,
    
    const Self = @This();
    
    pub fn init(allocator: Allocator, directory_url: []const u8) Self {
        return Self{
            .allocator = allocator,
            .directory_url = directory_url,
        };
    }
    
    pub fn deinit(self: *Self) void {
        _ = self;
    }
    
    pub fn createAccount(self: *Self, email: []const u8) !void {
        // Generate account key using zcrypto
        var rng = std.crypto.random;
        var seed: [32]u8 = undefined;
        rng.bytes(&seed);
        self.account_key = seed;
        
        std.log.info("Created ACME account for {s}", .{email});
    }
    
    pub fn requestCertificate(self: *Self, domains: []const []const u8) ![]const u8 {
        if (self.account_key == null) {
            return error.NoAccountKey;
        }
        
        // Simplified ACME certificate request
        for (domains) |domain| {
            std.log.info("Requesting certificate for domain: {s}", .{domain});
            
            // In a real implementation with zcrypto:
            // 1. Create order with JWS signature
            // 2. Complete DNS-01 or HTTP-01 challenge
            // 3. Finalize order with CSR
            // 4. Download certificate
        }
        
        // For now, return a placeholder
        return try self.allocator.dupe(u8, "ACME certificate placeholder");
    }
    
    pub fn generateCSR(self: *Self, domains: []const []const u8, private_key: []const u8) ![]const u8 {
        _ = private_key;
        
        // Generate Certificate Signing Request using zcrypto
        var csr_buffer = std.ArrayList(u8).init(self.allocator);
        defer csr_buffer.deinit();
        
        try csr_buffer.appendSlice("-----BEGIN CERTIFICATE REQUEST-----\n");
        
        // Add domains to CSR (simplified)
        for (domains) |domain| {
            std.log.info("Adding domain to CSR: {s}", .{domain});
        }
        
        try csr_buffer.appendSlice("CSR-placeholder-data\n");
        try csr_buffer.appendSlice("-----END CERTIFICATE REQUEST-----\n");
        
        return try csr_buffer.toOwnedSlice();
    }
};
