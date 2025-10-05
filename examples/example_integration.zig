//! Example Integration: How Parent Applications Should Use Wraith
//! This example shows how zwallet or other parent applications can integrate Wraith
//! with their own zcrypto implementation

const std = @import("std");
const wraith = @import("wraith");
// Assuming parent app has zcrypto available
// const zcrypto = @import("zcrypto");

/// Example of how a parent application (like zwallet) would implement the crypto interface
/// This would typically use zcrypto instead of std.crypto
pub const ZcryptoCryptoInterface = struct {
    
    /// Generate a new Ed25519 keypair using zcrypto
    pub fn generateKeypair() wraith.crypto_interface.KeypairResult {
        // In a real implementation with zcrypto:
        // const keypair = zcrypto.generateEd25519Keypair() catch |err| {
        //     return wraith.crypto_interface.KeypairResult{
        //         .public_key = std.mem.zeroes([32]u8),
        //         .secret_key = std.mem.zeroes([64]u8),
        //         .success = false,
        //         .error_msg = "zcrypto keypair generation failed",
        //     };
        // };
        
        // For this example, we'll use std.crypto as a placeholder
        var seed: [32]u8 = undefined;
        std.crypto.random.bytes(&seed);
        return keypairFromSeed(seed);
    }
    
    /// Create keypair from seed using zcrypto
    pub fn keypairFromSeed(seed: [32]u8) wraith.crypto_interface.KeypairResult {
        // Real implementation would use zcrypto:
        // const keypair = zcrypto.ed25519KeypairFromSeed(seed) catch |err| {
        //     return wraith.crypto_interface.KeypairResult{
        //         .public_key = std.mem.zeroes([32]u8),
        //         .secret_key = std.mem.zeroes([64]u8),
        //         .success = false,
        //         .error_msg = "zcrypto seed-based keypair generation failed",
        //     };
        // };
        
        // Placeholder using std.crypto
        const keypair = std.crypto.sign.Ed25519.KeyPair.create(seed) catch {
            return wraith.crypto_interface.KeypairResult{
                .public_key = std.mem.zeroes([32]u8),
                .secret_key = std.mem.zeroes([64]u8),
                .success = false,
                .error_msg = "Keypair generation failed",
            };
        };
        
        var secret_key: [64]u8 = undefined;
        @memcpy(secret_key[0..32], &keypair.secret_key);
        @memcpy(secret_key[32..64], &keypair.public_key);
        
        return wraith.crypto_interface.KeypairResult{
            .public_key = keypair.public_key,
            .secret_key = secret_key,
            .success = true,
        };
    }
    
    /// Sign message using zcrypto
    pub fn sign(message: []const u8, secret_key: [64]u8) [64]u8 {
        // Real implementation:
        // return zcrypto.ed25519Sign(message, secret_key[0..32]);
        
        // Placeholder
        const keypair = std.crypto.sign.Ed25519.KeyPair{
            .secret_key = secret_key[0..32].*,
            .public_key = secret_key[32..64].*,
        };
        return keypair.sign(message, null);
    }
    
    /// Verify signature using zcrypto
    pub fn verify(message: []const u8, signature: [64]u8, public_key: [32]u8) bool {
        // Real implementation:
        // return zcrypto.ed25519Verify(message, signature, public_key);
        
        // Placeholder
        std.crypto.sign.Ed25519.verify(signature, message, public_key) catch return false;
        return true;
    }
    
    /// Hash using zcrypto
    pub fn hashBytes(data: []const u8) [32]u8 {
        // Real implementation:
        // return zcrypto.sha256(data);
        
        // Placeholder
        return std.crypto.hash.sha2.Sha256.hash(data);
    }
    
    /// SHA256 using zcrypto
    pub fn sha256Bytes(data: []const u8) [32]u8 {
        // Real implementation:
        // return zcrypto.sha256(data);
        
        // Placeholder
        return std.crypto.hash.sha2.Sha256.hash(data);
    }
    
    /// SHA384 using zcrypto
    pub fn sha384Bytes(data: []const u8) [48]u8 {
        // Real implementation:
        // return zcrypto.sha384(data);
        
        // Placeholder
        return std.crypto.hash.sha2.Sha384.hash(data);
    }
    
    /// Random bytes using zcrypto
    pub fn randomBytesImpl(buffer: []u8) void {
        // Real implementation:
        // zcrypto.randomBytes(buffer);
        
        // Placeholder
        std.crypto.random.bytes(buffer);
    }
    
    /// Generate TLS keypair using zcrypto
    pub fn generateTlsKeyPair() wraith.crypto_interface.TlsKeyPairResult {
        // Real implementation would use zcrypto to generate proper TLS keys:
        // const tls_keypair = zcrypto.generateTlsKeypair() catch |err| {
        //     return wraith.crypto_interface.TlsKeyPairResult{
        //         .key_pair = wraith.crypto_interface.TlsKeyPair{
        //             .public_key = "",
        //             .private_key = "",
        //         },
        //         .success = false,
        //         .error_msg = "zcrypto TLS keypair generation failed",
        //     };
        // };
        
        // Placeholder implementation
        return wraith.crypto_interface.TlsKeyPairResult{
            .key_pair = wraith.crypto_interface.TlsKeyPair{
                .public_key = "-----BEGIN PUBLIC KEY-----\n(zcrypto generated key)\n-----END PUBLIC KEY-----",
                .private_key = "-----BEGIN PRIVATE KEY-----\n(zcrypto generated key)\n-----END PRIVATE KEY-----",
            },
            .success = true,
        };
    }
    
    /// Create self-signed certificate using zcrypto
    pub fn createSelfSignedCert(hostname: []const u8, key_pair: wraith.crypto_interface.TlsKeyPair) wraith.crypto_interface.CertificateResult {
        // Real implementation:
        // const cert = zcrypto.createSelfSignedCert(hostname, key_pair.private_key) catch |err| {
        //     return wraith.crypto_interface.CertificateResult{
        //         .cert_pem = "",
        //         .success = false,
        //         .error_msg = "zcrypto certificate generation failed",
        //     };
        // };
        
        _ = key_pair; // Unused in placeholder
        
        // Placeholder - would generate real X.509 certificate with zcrypto
        var cert_buffer: [2048]u8 = undefined;
        const cert_pem = std.fmt.bufPrint(&cert_buffer,
            \\-----BEGIN CERTIFICATE-----
            \\MIICdTCCAV0CAQAwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwH{s}w
            \\HhcNMjUwNjI0MDAwMDAwWhcNMjYwNjI0MDAwMDAwWjASMRAwDgYDVQQDDAdkZXYt
            \\c2VydmVyMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE(zcrypto-generated-key)
            \\MA0GCSqGSIb3DQEBCwUAA4IBAQBDev-cert-generated-by-zcrypto
            \\-----END CERTIFICATE-----
        , .{hostname}) catch "cert generation error";
        
        return wraith.crypto_interface.CertificateResult{
            .cert_pem = cert_pem,
            .success = true,
        };
    }
    
    /// AEAD encryption using zcrypto
    pub fn aeadEncrypt(plaintext: []const u8, key: []const u8, nonce: []const u8) wraith.crypto_interface.EncryptResult {
        // Real implementation:
        // const result = zcrypto.aeadEncrypt(plaintext, key, nonce) catch |err| {
        //     return wraith.crypto_interface.EncryptResult{
        //         .ciphertext = "",
        //         .tag = std.mem.zeroes([16]u8),
        //         .success = false,
        //         .error_msg = "zcrypto AEAD encryption failed",
        //     };
        // };
        
        _ = plaintext; _ = key; _ = nonce; // Unused in placeholder
        
        // Placeholder
        return wraith.crypto_interface.EncryptResult{
            .ciphertext = "zcrypto_encrypted_data",
            .tag = std.mem.zeroes([16]u8),
            .success = true,
        };
    }
    
    /// AEAD decryption using zcrypto
    pub fn aeadDecrypt(ciphertext: []const u8, key: []const u8, nonce: []const u8) wraith.crypto_interface.DecryptResult {
        // Real implementation:
        // const result = zcrypto.aeadDecrypt(ciphertext, key, nonce) catch |err| {
        //     return wraith.crypto_interface.DecryptResult{
        //         .plaintext = "",
        //         .success = false,
        //         .error_msg = "zcrypto AEAD decryption failed",
        //     };
        // };
        
        _ = ciphertext; _ = key; _ = nonce; // Unused in placeholder
        
        // Placeholder
        return wraith.crypto_interface.DecryptResult{
            .plaintext = "zcrypto_decrypted_data",
            .success = true,
        };
    }
    
    /// Create the crypto interface for parent application
    pub fn createInterface() wraith.CryptoInterface {
        return wraith.CryptoInterface{
            .generateKeypairFn = generateKeypair,
            .keypairFromSeedFn = keypairFromSeed,
            .signFn = sign,
            .verifyFn = verify,
            .hashFn = hashBytes,
            .sha256Fn = sha256Bytes,
            .sha384Fn = sha384Bytes,
            .randomBytesFn = randomBytesImpl,
            .generateTlsKeyPairFn = generateTlsKeyPair,
            .createSelfSignedCertFn = createSelfSignedCert,
            .aeadEncryptFn = aeadEncrypt,
            .aeadDecryptFn = aeadDecrypt,
        };
    }
};

/// Example of how a parent application would initialize and use Wraith
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== Parent Application Integration Example ===\n", .{});
    
    // Step 1: Create crypto interface using your zcrypto implementation
    std.debug.print("🔧 Creating zcrypto-based crypto interface...\n", .{});
    const crypto_interface = ZcryptoCryptoInterface.createInterface();
    
    // Step 2: Initialize Wraith with your crypto interface
    std.debug.print("🔌 Setting crypto interface in Wraith...\n", .{});
    wraith.setCryptoInterface(crypto_interface);
    
    // Step 3: Verify crypto interface is working
    std.debug.print("✅ Testing crypto interface...\n", .{});
    const test_data = "Hello, Wraith!";
    const hash_result = try wraith.crypto_interface.hash(test_data);
    std.debug.print("   Hash test successful: {x}\n", .{std.fmt.fmtSliceHexLower(&hash_result)});
    
    // Step 4: Configure and start Wraith server
    std.debug.print("🚀 Starting Wraith server with injected crypto...\n", .{});
    const server_config = wraith.server.ServerConfig{
        .bind_address = "::1",
        .port = 8443,
        .enable_tls13_only = true,
    };
    
    try wraith.server.startWithConfig(allocator, server_config);
    
    std.debug.print("✅ Wraith integration example completed successfully!\n", .{});
    std.debug.print("\n📋 Integration Summary:\n", .{});
    std.debug.print("   • Crypto: zcrypto (injected by parent app)\n", .{});
    std.debug.print("   • Transport: QUIC/HTTP3\n", .{});
    std.debug.print("   • TLS: 1.3 with parent's crypto primitives\n", .{});
    std.debug.print("   • Dependencies: Lightweight (no bundled crypto)\n", .{});
}

/// Test the crypto interface integration
test "crypto interface integration" {
    const interface = ZcryptoCryptoInterface.createInterface();
    wraith.setCryptoInterface(interface);
    
    // Test hashing
    const test_data = "test";
    const hash_result = try wraith.crypto_interface.hash(test_data);
    try std.testing.expect(hash_result.len == 32);
    
    // Test keypair generation
    const keypair_result = try wraith.crypto_interface.generateKeypair();
    try std.testing.expect(keypair_result.success);
    try std.testing.expect(keypair_result.public_key.len == 32);
    try std.testing.expect(keypair_result.secret_key.len == 64);
    
    // Test signing and verification
    const signature = try wraith.crypto_interface.sign(test_data, keypair_result.secret_key);
    const is_valid = try wraith.crypto_interface.verify(test_data, signature, keypair_result.public_key);
    try std.testing.expect(is_valid);
}