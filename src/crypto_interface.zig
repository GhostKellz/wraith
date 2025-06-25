//! Crypto Interface for Wraith
//! Allows parent applications to inject crypto primitives instead of bundling zcrypto

const std = @import("std");

/// Crypto primitives that parent applications must provide
pub const CryptoInterface = struct {
    // TLS & Certificate functions
    generateKeypairFn: *const fn () KeypairResult,
    keypairFromSeedFn: *const fn (seed: [32]u8) KeypairResult,
    signFn: *const fn (message: []const u8, secret_key: [64]u8) [64]u8,
    verifyFn: *const fn (message: []const u8, signature: [64]u8, public_key: [32]u8) bool,
    
    // Hashing functions
    hashFn: *const fn (data: []const u8) [32]u8,
    sha256Fn: *const fn (data: []const u8) [32]u8,
    sha384Fn: *const fn (data: []const u8) [48]u8,
    
    // Random number generation
    randomBytesFn: *const fn (buffer: []u8) void,
    
    // TLS specific functions
    generateTlsKeyPairFn: *const fn () TlsKeyPairResult,
    createSelfSignedCertFn: *const fn (hostname: []const u8, key_pair: TlsKeyPair) CertificateResult,
    
    // AEAD encryption for QUIC
    aeadEncryptFn: *const fn (plaintext: []const u8, key: []const u8, nonce: []const u8) EncryptResult,
    aeadDecryptFn: *const fn (ciphertext: []const u8, key: []const u8, nonce: []const u8) DecryptResult,
};

/// Global crypto interface instance
var crypto_interface: ?CryptoInterface = null;

/// Set the crypto interface (must be called before using any crypto functions)
pub fn setCryptoInterface(interface: CryptoInterface) void {
    crypto_interface = interface;
}

/// Get the current crypto interface
pub fn getCryptoInterface() ?CryptoInterface {
    return crypto_interface;
}

/// Check if crypto interface is available
pub fn hasCryptoInterface() bool {
    return crypto_interface != null;
}

// Result types
pub const KeypairResult = struct {
    public_key: [32]u8,
    secret_key: [64]u8,
    success: bool,
    error_msg: ?[]const u8 = null,
};

pub const TlsKeyPair = struct {
    public_key: []const u8,
    private_key: []const u8,
};

pub const TlsKeyPairResult = struct {
    key_pair: TlsKeyPair,
    success: bool,
    error_msg: ?[]const u8 = null,
};

pub const CertificateResult = struct {
    cert_pem: []const u8,
    success: bool,
    error_msg: ?[]const u8 = null,
};

pub const EncryptResult = struct {
    ciphertext: []const u8,
    tag: [16]u8,
    success: bool,
    error_msg: ?[]const u8 = null,
};

pub const DecryptResult = struct {
    plaintext: []const u8,
    success: bool,
    error_msg: ?[]const u8 = null,
};

// Convenience functions that use the injected interface
pub fn generateKeypair() !KeypairResult {
    const interface = crypto_interface orelse return error.CryptoInterfaceNotSet;
    return interface.generateKeypairFn();
}

pub fn keypairFromSeed(seed: [32]u8) !KeypairResult {
    const interface = crypto_interface orelse return error.CryptoInterfaceNotSet;
    return interface.keypairFromSeedFn(seed);
}

pub fn sign(message: []const u8, secret_key: [64]u8) ![64]u8 {
    const interface = crypto_interface orelse return error.CryptoInterfaceNotSet;
    return interface.signFn(message, secret_key);
}

pub fn verify(message: []const u8, signature: [64]u8, public_key: [32]u8) !bool {
    const interface = crypto_interface orelse return error.CryptoInterfaceNotSet;
    return interface.verifyFn(message, signature, public_key);
}

pub fn hash(data: []const u8) ![32]u8 {
    const interface = crypto_interface orelse return error.CryptoInterfaceNotSet;
    return interface.hashFn(data);
}

pub fn sha256(data: []const u8) ![32]u8 {
    const interface = crypto_interface orelse return error.CryptoInterfaceNotSet;
    return interface.sha256Fn(data);
}

pub fn sha384(data: []const u8) ![48]u8 {
    const interface = crypto_interface orelse return error.CryptoInterfaceNotSet;
    return interface.sha384Fn(data);
}

pub fn randomBytes(buffer: []u8) !void {
    const interface = crypto_interface orelse return error.CryptoInterfaceNotSet;
    return interface.randomBytesFn(buffer);
}

pub fn generateTlsKeyPair() !TlsKeyPairResult {
    const interface = crypto_interface orelse return error.CryptoInterfaceNotSet;
    return interface.generateTlsKeyPairFn();
}

pub fn createSelfSignedCert(hostname: []const u8, key_pair: TlsKeyPair) !CertificateResult {
    const interface = crypto_interface orelse return error.CryptoInterfaceNotSet;
    return interface.createSelfSignedCertFn(hostname, key_pair);
}

pub fn aeadEncrypt(plaintext: []const u8, key: []const u8, nonce: []const u8) !EncryptResult {
    const interface = crypto_interface orelse return error.CryptoInterfaceNotSet;
    return interface.aeadEncryptFn(plaintext, key, nonce);
}

pub fn aeadDecrypt(ciphertext: []const u8, key: []const u8, nonce: []const u8) !DecryptResult {
    const interface = crypto_interface orelse return error.CryptoInterfaceNotSet;
    return interface.aeadDecryptFn(ciphertext, key, nonce);
}

/// Example implementation using std.crypto for development/testing
pub const ExampleStdCryptoInterface = struct {
    pub fn generateKeypair() KeypairResult {
        var seed: [32]u8 = undefined;
        std.crypto.random.bytes(&seed);
        return keypairFromSeed(seed);
    }
    
    pub fn keypairFromSeed(seed: [32]u8) KeypairResult {
        const keypair = std.crypto.sign.Ed25519.KeyPair.create(seed) catch {
            return KeypairResult{
                .public_key = std.mem.zeroes([32]u8),
                .secret_key = std.mem.zeroes([64]u8),
                .success = false,
                .error_msg = "Failed to create keypair",
            };
        };
        
        var secret_key: [64]u8 = undefined;
        @memcpy(secret_key[0..32], &keypair.secret_key);
        @memcpy(secret_key[32..64], &keypair.public_key);
        
        return KeypairResult{
            .public_key = keypair.public_key,
            .secret_key = secret_key,
            .success = true,
        };
    }
    
    pub fn sign(message: []const u8, secret_key: [64]u8) [64]u8 {
        const keypair = std.crypto.sign.Ed25519.KeyPair{
            .secret_key = secret_key[0..32].*,
            .public_key = secret_key[32..64].*,
        };
        return keypair.sign(message, null);
    }
    
    pub fn verify(message: []const u8, signature: [64]u8, public_key: [32]u8) bool {
        std.crypto.sign.Ed25519.verify(signature, message, public_key) catch return false;
        return true;
    }
    
    pub fn hashBytes(data: []const u8) [32]u8 {
        return std.crypto.hash.sha2.Sha256.hash(data);
    }
    
    pub fn sha256Bytes(data: []const u8) [32]u8 {
        return std.crypto.hash.sha2.Sha256.hash(data);
    }
    
    pub fn sha384Bytes(data: []const u8) [48]u8 {
        return std.crypto.hash.sha2.Sha384.hash(data);
    }
    
    pub fn randomBytesImpl(buffer: []u8) void {
        std.crypto.random.bytes(buffer);
    }
    
    pub fn generateTlsKeyPair() TlsKeyPairResult {
        // Generate Ed25519 key pair for TLS
        var seed: [32]u8 = undefined;
        std.crypto.random.bytes(&seed);
        
        const keypair = std.crypto.sign.Ed25519.KeyPair.create(seed) catch {
            return TlsKeyPairResult{
                .key_pair = TlsKeyPair{
                    .public_key = "",
                    .private_key = "",
                },
                .success = false,
                .error_msg = "Failed to generate TLS keypair",
            };
        };
        
        // In a real implementation, these would be properly formatted PEM keys
        const public_pem = "-----BEGIN PUBLIC KEY-----\n(base64 encoded key)\n-----END PUBLIC KEY-----";
        const private_pem = "-----BEGIN PRIVATE KEY-----\n(base64 encoded key)\n-----END PRIVATE KEY-----";
        
        return TlsKeyPairResult{
            .key_pair = TlsKeyPair{
                .public_key = public_pem,
                .private_key = private_pem,
            },
            .success = true,
        };
    }
    
    pub fn createSelfSignedCert(hostname: []const u8, key_pair: TlsKeyPair) CertificateResult {
        _ = hostname;
        _ = key_pair;
        
        // Simplified cert generation for example
        const cert_pem = 
            \\-----BEGIN CERTIFICATE-----
            \\MIIBkTCB+wIJALQ+5+5+5+5+MA0GCSqGSIb3DQEBCwUAMBUxEzARBgNVBAMMCmxv
            \\Y2FsaG9zdDAeFw0yNTA2MjQwMDAwMDBaFw0yNjA2MjQwMDAwMDBaMBUxEzARBgNV
            \\BAMMCmxvY2FsaG9zdDBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABKp4/5+5+5+5
            \\+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5+5
            \\-----END CERTIFICATE-----
        ;
        
        return CertificateResult{
            .cert_pem = cert_pem,
            .success = true,
        };
    }
    
    pub fn aeadEncrypt(plaintext: []const u8, key: []const u8, nonce: []const u8) EncryptResult {
        _ = plaintext;
        _ = key;
        _ = nonce;
        
        // Simplified AEAD encryption for example
        return EncryptResult{
            .ciphertext = "encrypted_data",
            .tag = std.mem.zeroes([16]u8),
            .success = true,
        };
    }
    
    pub fn aeadDecrypt(ciphertext: []const u8, key: []const u8, nonce: []const u8) DecryptResult {
        _ = ciphertext;
        _ = key;
        _ = nonce;
        
        // Simplified AEAD decryption for example
        return DecryptResult{
            .plaintext = "decrypted_data",
            .success = true,
        };
    }
    
    /// Create the interface struct with function pointers
    pub fn createInterface() CryptoInterface {
        return CryptoInterface{
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