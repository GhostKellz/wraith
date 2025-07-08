# 🕸️ Shroud API Reference

> Complete API documentation for the Shroud v1.0 framework

---

## Table of Contents

- [Framework API](#framework-api)
- [GhostCipher API](#ghostcipher-api)
- [Sigil API](#sigil-api)
- [GhostWire API](#ghostwire-api)
- [Keystone API](#keystone-api)
- [ZNS API](#zns-api)
- [ShadowCraft API](#shadowcraft-api)
- [Guardian API](#guardian-api)
- [Covenant API](#covenant-api)
- [GWallet API](#gwallet-api)
- [Error Handling](#error-handling)
- [FFI Bindings](#ffi-bindings)

---

## Framework API

### Core Framework

```zig
const shroud = @import("shroud");

// Version information
pub fn version() []const u8

// Error types
pub const ShroudError = error{
    ModuleInitFailed,
    CryptoError,
    NetworkError,
    IdentityError,
    LedgerError,
};

// Module exports
pub const ghostcipher = @import("ghostcipher");
pub const sigil = @import("sigil");
pub const ghostwire = @import("ghostwire");
pub const keystone = @import("keystone");
pub const zns = @import("zns");
pub const shadowcraft = @import("shadowcraft");
pub const guardian = @import("guardian");
pub const covenant = @import("covenant");
pub const gwallet = @import("gwallet");

// Clean v0.4.0 API - Access modules directly:
// shroud.ghostcipher.zcrypto (replaces old zcrypto)
// shroud.ghostcipher.zsig (replaces old zsig)  
// shroud.sigil (replaces old realid)
```

### Module Integration

```zig
// Import specific modules
const ghostcipher = shroud.ghostcipher;
const sigil = shroud.sigil;
const ghostwire = shroud.ghostwire;
const keystone = shroud.keystone;
```

---

## GhostCipher API

### ZCrypto Core

```zig
const zcrypto = shroud.ghostcipher.zcrypto;

// Symmetric encryption
pub const sym = struct {
    pub const Algorithm = enum {
        aes_256_gcm,
        chacha20_poly1305,
        xchacha20_poly1305,
    };

    pub fn encrypt(
        algorithm: Algorithm,
        key: []const u8,
        nonce: []const u8,
        plaintext: []const u8,
        ciphertext: []u8,
        tag: []u8
    ) !void;

    pub fn decrypt(
        algorithm: Algorithm,
        key: []const u8,
        nonce: []const u8,
        ciphertext: []const u8,
        tag: []const u8,
        plaintext: []u8
    ) !void;
};

// Asymmetric cryptography
pub const asym = struct {
    pub const Algorithm = enum {
        ed25519,
        secp256k1,
        x25519,
        p256,
    };

    pub const KeyPair = struct {
        public_key: []const u8,
        private_key: []const u8,
    };

    pub fn generateKeyPair(algorithm: Algorithm, allocator: std.mem.Allocator) !KeyPair;
    pub fn sign(private_key: []const u8, message: []const u8, allocator: std.mem.Allocator) ![]u8;
    pub fn verify(public_key: []const u8, message: []const u8, signature: []const u8) bool;
};

// Hash functions
pub const hash = struct {
    pub const Algorithm = enum {
        sha256,
        sha3_256,
        blake3,
        blake2b,
    };

    pub fn digest(algorithm: Algorithm, input: []const u8, output: []u8) void;
    pub fn hmac(algorithm: Algorithm, key: []const u8, message: []const u8, output: []u8) void;
};

// Key derivation
pub const kdf = struct {
    pub const Algorithm = enum {
        pbkdf2,
        argon2id,
        hkdf,
        scrypt,
    };

    pub fn derive(
        algorithm: Algorithm,
        password: []const u8,
        salt: []const u8,
        iterations: u32,
        output: []u8
    ) !void;
};

// Post-quantum cryptography
pub const pq = struct {
    pub const ml_kem = struct {
        pub const KeyPair512 = struct {
            public_key: [800]u8,
            private_key: [1632]u8,
        };

        pub const KeyPair768 = struct {
            public_key: [1184]u8,
            private_key: [2400]u8,
        };

        pub const KeyPair1024 = struct {
            public_key: [1568]u8,
            private_key: [3168]u8,
        };

        pub fn generateKeyPair512() !KeyPair512;
        pub fn generateKeyPair768() !KeyPair768;
        pub fn generateKeyPair1024() !KeyPair1024;
        
        pub fn encapsulate512(public_key: [800]u8) !struct { ciphertext: [768]u8, shared_secret: [32]u8 };
        pub fn decapsulate512(private_key: [1632]u8, ciphertext: [768]u8) ![32]u8;
    };
};
```

### ZSig Digital Signatures

```zig
const zsig = shroud.ghostcipher.zsig;

pub const Algorithm = enum {
    ed25519,
    secp256k1,
    rsa_pss,
    dilithium2,
    dilithium3,
    dilithium5,
};

pub const KeyPair = struct {
    algorithm: Algorithm,
    public_key: []const u8,
    private_key: []const u8,
};

pub const Signature = struct {
    algorithm: Algorithm,
    bytes: []const u8,
};

// Key management
pub fn generateKeyPair(algorithm: Algorithm, allocator: std.mem.Allocator) !KeyPair;
pub fn importPrivateKey(algorithm: Algorithm, key_data: []const u8, allocator: std.mem.Allocator) !KeyPair;
pub fn exportPublicKey(keypair: KeyPair, allocator: std.mem.Allocator) ![]u8;

// Signing operations
pub fn sign(keypair: KeyPair, message: []const u8, allocator: std.mem.Allocator) !Signature;
pub fn verify(public_key: []const u8, algorithm: Algorithm, message: []const u8, signature: Signature) bool;

// Batch operations
pub fn signBatch(keypair: KeyPair, messages: []const []const u8, allocator: std.mem.Allocator) ![]Signature;
pub fn verifyBatch(public_key: []const u8, algorithm: Algorithm, messages: []const []const u8, signatures: []const Signature) ![]bool;
```

---

## Sigil API

### Identity Management

```zig
const sigil = shroud.sigil;

// Core types
pub const RealIDKeyPair = struct {
    private_key: RealIDPrivateKey,
    public_key: RealIDPublicKey,
};

pub const RealIDPrivateKey = struct {
    bytes: [64]u8,
};

pub const RealIDPublicKey = struct {
    bytes: [32]u8,
};

pub const RealIDSignature = struct {
    bytes: [64]u8,
};

pub const QID = struct {
    bytes: [16]u8, // IPv6 address
};

pub const DeviceFingerprint = struct {
    bytes: [32]u8,
};

pub const RealIDError = error{
    InvalidPassphrase,
    KeyGenerationFailed,
    SigningFailed,
    VerificationFailed,
    InvalidSignature,
    InvalidPublicKey,
    DeviceFingerprintFailed,
};

// Identity generation
pub fn realid_generate_from_passphrase(passphrase: []const u8) !RealIDKeyPair;
pub fn realid_generate_from_passphrase_with_device(
    passphrase: []const u8,
    device_fingerprint: DeviceFingerprint
) !RealIDKeyPair;

// Signing and verification
pub fn realid_sign(data: []const u8, private_key: RealIDPrivateKey) !RealIDSignature;
pub fn realid_verify(signature: RealIDSignature, data: []const u8, public_key: RealIDPublicKey) bool;

// QID operations
pub fn realid_qid_from_pubkey(public_key: RealIDPublicKey) QID;
pub fn qid_to_string(qid: QID, allocator: std.mem.Allocator) ![]u8;
pub fn qid_from_string(qid_str: []const u8) !QID;

// Device fingerprinting
pub fn generate_device_fingerprint(allocator: std.mem.Allocator) !DeviceFingerprint;
```

---

## GhostWire API

### Unified Server

```zig
const ghostwire = shroud.ghostwire;

pub const UnifiedServerConfig = struct {
    http1_port: u16 = 8080,
    http2_port: u16 = 8443,
    http3_port: u16 = 443,
    grpc_port: u16 = 50051,
    websocket_port: u16 = 8765,
    enable_tls: bool = true,
    cert_path: ?[]const u8 = null,
    key_path: ?[]const u8 = null,
    enable_compression: bool = true,
    max_connections: u32 = 10000,
    enable_ipv6: bool = true,
    bind_address: []const u8 = "0.0.0.0",
};

pub const UnifiedServer = struct {
    pub fn init(allocator: std.mem.Allocator, config: UnifiedServerConfig) !UnifiedServer;
    pub fn deinit(self: *UnifiedServer) void;
    pub fn start(self: *UnifiedServer) !void;
    pub fn stop(self: *UnifiedServer) void;
    pub fn addHandler(self: *UnifiedServer, path: []const u8, handler: HandlerFn) void;
    pub fn addMiddleware(self: *UnifiedServer, middleware: MiddlewareFn) void;
};

pub const UnifiedRequest = struct {
    method: []const u8,
    path: []const u8,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    protocol: NetworkProtocol,
    remote_addr: []const u8,
    identity: ?sigil.RealIDPublicKey,
};

pub const UnifiedResponse = struct {
    status: u16,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    
    pub fn setStatus(self: *UnifiedResponse, status: u16) void;
    pub fn setHeader(self: *UnifiedResponse, key: []const u8, value: []const u8) void;
    pub fn setBody(self: *UnifiedResponse, body: []const u8) void;
};

pub const HandlerFn = *const fn (request: *UnifiedRequest, response: *UnifiedResponse) anyerror!void;
pub const MiddlewareFn = *const fn (request: *UnifiedRequest, response: *UnifiedResponse, next: HandlerFn) anyerror!void;

// Convenience functions
pub fn createUnifiedServer(allocator: std.mem.Allocator, config: UnifiedServerConfig) !UnifiedServer;
```

### HTTP Client

```zig
pub const HttpClient = struct {
    pub const Config = struct {
        timeout_ms: u32 = 30000,
        max_redirects: u8 = 10,
        user_agent: []const u8 = "GhostWire/1.0",
        enable_compression: bool = true,
        verify_tls: bool = true,
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) !HttpClient;
    pub fn deinit(self: *HttpClient) void;
    
    pub fn get(self: *HttpClient, url: []const u8) !HttpResponse;
    pub fn post(self: *HttpClient, url: []const u8, body: []const u8, content_type: []const u8) !HttpResponse;
    pub fn put(self: *HttpClient, url: []const u8, body: []const u8, content_type: []const u8) !HttpResponse;
    pub fn delete(self: *HttpClient, url: []const u8) !HttpResponse;
    
    pub fn request(self: *HttpClient, method: []const u8, url: []const u8, headers: ?std.StringHashMap([]const u8), body: ?[]const u8) !HttpResponse;
};

pub const HttpResponse = struct {
    status: u16,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    
    pub fn deinit(self: *HttpResponse, allocator: std.mem.Allocator) void;
};
```

### WebSocket

```zig
pub const websocket = struct {
    pub const WebSocketServerConfig = struct {
        port: u16 = 8765,
        max_connections: u32 = 1000,
        ping_interval_ms: u32 = 30000,
        max_message_size: u32 = 1024 * 1024, // 1MB
        enable_compression: bool = true,
    };

    pub const WebSocketServer = struct {
        pub fn init(allocator: std.mem.Allocator, config: WebSocketServerConfig) !WebSocketServer;
        pub fn deinit(self: *WebSocketServer) void;
        pub fn start(self: *WebSocketServer) !void;
        pub fn stop(self: *WebSocketServer) void;
        pub fn broadcast(self: *WebSocketServer, message: []const u8) !void;
        pub fn onConnect(self: *WebSocketServer, callback: *const fn (connection: *WebSocketConnection) void) void;
        pub fn onMessage(self: *WebSocketServer, callback: *const fn (connection: *WebSocketConnection, message: []const u8) void) void;
        pub fn onDisconnect(self: *WebSocketServer, callback: *const fn (connection: *WebSocketConnection) void) void;
    };

    pub const WebSocketClientConfig = struct {
        timeout_ms: u32 = 30000,
        ping_interval_ms: u32 = 30000,
        max_message_size: u32 = 1024 * 1024,
        enable_compression: bool = true,
    };

    pub const WebSocketClient = struct {
        pub fn init(allocator: std.mem.Allocator, url: []const u8, config: WebSocketClientConfig) !WebSocketClient;
        pub fn deinit(self: *WebSocketClient) void;
        pub fn connect(self: *WebSocketClient) !void;
        pub fn disconnect(self: *WebSocketClient) void;
        pub fn send(self: *WebSocketClient, message: []const u8) !void;
        pub fn receive(self: *WebSocketClient, buffer: []u8) !usize;
        pub fn onMessage(self: *WebSocketClient, callback: *const fn (message: []const u8) void) void;
    };

    pub const WebSocketConnection = struct {
        pub fn send(self: *WebSocketConnection, message: []const u8) !void;
        pub fn close(self: *WebSocketConnection) void;
        pub fn getRemoteAddress(self: *WebSocketConnection) []const u8;
    };
};
```

### gRPC

```zig
pub const grpc = struct {
    pub const GrpcConfig = struct {
        port: u16 = 50051,
        max_connections: u32 = 1000,
        enable_reflection: bool = true,
        enable_health_check: bool = true,
    };

    pub const GrpcServer = struct {
        pub fn init(allocator: std.mem.Allocator, config: GrpcConfig) !GrpcServer;
        pub fn deinit(self: *GrpcServer) void;
        pub fn start(self: *GrpcServer) !void;
        pub fn stop(self: *GrpcServer) void;
        pub fn addService(self: *GrpcServer, service: anytype) void;
    };

    pub const GrpcClient = struct {
        pub fn init(allocator: std.mem.Allocator, endpoint: []const u8) !GrpcClient;
        pub fn deinit(self: *GrpcClient) void;
        pub fn call(self: *GrpcClient, service: []const u8, method: []const u8, request: []const u8) ![]u8;
    };

    pub const GrpcMessage = struct {
        data: []const u8,
        metadata: std.StringHashMap([]const u8),
    };

    pub const GrpcStatus = enum {
        ok,
        cancelled,
        unknown,
        invalid_argument,
        deadline_exceeded,
        not_found,
        already_exists,
        permission_denied,
        resource_exhausted,
        failed_precondition,
        aborted,
        out_of_range,
        unimplemented,
        internal,
        unavailable,
        data_loss,
        unauthenticated,
    };
};
```

### IPv6 Stack

```zig
pub const ipv6 = struct {
    pub const IPv6Config = struct {
        enable_auto_config: bool = true,
        enable_privacy_extensions: bool = true,
        enable_multicast_discovery: bool = true,
        router_solicitation_interval: u32 = 4000,
    };

    pub const IPv6Address = struct {
        bytes: [16]u8,
        
        pub fn fromString(addr_str: []const u8) !IPv6Address;
        pub fn toString(self: IPv6Address, allocator: std.mem.Allocator) ![]u8;
        pub fn isGlobal(self: IPv6Address) bool;
        pub fn isLinkLocal(self: IPv6Address) bool;
        pub fn isMulticast(self: IPv6Address) bool;
    };

    pub const IPv6Subnet = struct {
        network: IPv6Address,
        prefix_length: u8,
        
        pub fn contains(self: IPv6Subnet, address: IPv6Address) bool;
    };

    pub const IPv6Stack = struct {
        pub fn init(allocator: std.mem.Allocator, config: IPv6Config) IPv6Stack;
        pub fn deinit(self: *IPv6Stack) void;
        pub fn configure(self: *IPv6Stack) !void;
        pub fn getAddresses(self: *IPv6Stack) ![]IPv6Address;
        pub fn addAddress(self: *IPv6Stack, address: IPv6Address) !void;
        pub fn removeAddress(self: *IPv6Stack, address: IPv6Address) !void;
    };

    pub const IPv6Discovery = struct {
        pub fn init(allocator: std.mem.Allocator) !IPv6Discovery;
        pub fn deinit(self: *IPv6Discovery) void;
        pub fn discoverServices(self: *IPv6Discovery, service_type: []const u8) ![]ServiceInfo;
        pub fn announceService(self: *IPv6Discovery, service: ServiceInfo) !void;
    };

    pub const ServiceInfo = struct {
        name: []const u8,
        address: IPv6Address,
        port: u16,
        txt_records: std.StringHashMap([]const u8),
    };
};
```

---

## Keystone API

### Ledger Management

```zig
const keystone = shroud.keystone;

pub const AccountType = enum {
    asset,
    liability,
    equity,
    revenue,
    expense,
};

pub const Account = struct {
    id: u64,
    name: []const u8,
    account_type: AccountType,
    balance: FixedPoint,
    parent_id: ?u64,
    is_active: bool,
    
    pub fn init(id: u64, name: []const u8, account_type: AccountType) Account;
    pub fn credit(self: *Account, amount: FixedPoint) void;
    pub fn debit(self: *Account, amount: FixedPoint) void;
    pub fn getBalance(self: Account) FixedPoint;
};

pub const Transaction = struct {
    id: u64,
    description: []const u8,
    date: i64, // Unix timestamp
    entries: []JournalEntry,
    signature: ?[]const u8,
    
    pub fn init(allocator: std.mem.Allocator, id: u64, description: []const u8) !Transaction;
    pub fn deinit(self: *Transaction, allocator: std.mem.Allocator) void;
    pub fn addEntry(self: *Transaction, entry: JournalEntry) !void;
    pub fn isBalanced(self: Transaction) bool;
    pub fn sign(self: *Transaction, private_key: []const u8) !void;
    pub fn verify(self: Transaction, public_key: []const u8) bool;
};

pub const JournalEntry = struct {
    account_id: u64,
    debit_amount: FixedPoint,
    credit_amount: FixedPoint,
    description: []const u8,
};

pub const Ledger = struct {
    pub fn init(allocator: std.mem.Allocator) !Ledger;
    pub fn deinit(self: *Ledger) void;
    
    // Account management
    pub fn createAccount(self: *Ledger, name: []const u8, account_type: AccountType) !u64;
    pub fn getAccount(self: *Ledger, id: u64) ?*Account;
    pub fn updateAccount(self: *Ledger, id: u64, account: Account) !void;
    pub fn deleteAccount(self: *Ledger, id: u64) !void;
    pub fn listAccounts(self: *Ledger) []Account;
    
    // Transaction management
    pub fn postTransaction(self: *Ledger, transaction: Transaction) !void;
    pub fn getTransaction(self: *Ledger, id: u64) ?Transaction;
    pub fn listTransactions(self: *Ledger, from_date: ?i64, to_date: ?i64) ![]Transaction;
    
    // Reporting
    pub fn generateTrialBalance(self: *Ledger, allocator: std.mem.Allocator) ![]AccountBalance;
    pub fn generateIncomeStatement(self: *Ledger, from_date: i64, to_date: i64, allocator: std.mem.Allocator) !IncomeStatement;
    pub fn generateBalanceSheet(self: *Ledger, as_of_date: i64, allocator: std.mem.Allocator) !BalanceSheet;
};

pub const FixedPoint = struct {
    value: i64,
    scale: u8,
    
    pub fn init(value: i64, scale: u8) FixedPoint;
    pub fn fromFloat(value: f64, scale: u8) FixedPoint;
    pub fn toFloat(self: FixedPoint) f64;
    pub fn add(self: FixedPoint, other: FixedPoint) FixedPoint;
    pub fn subtract(self: FixedPoint, other: FixedPoint) FixedPoint;
    pub fn multiply(self: FixedPoint, other: FixedPoint) FixedPoint;
    pub fn divide(self: FixedPoint, other: FixedPoint) FixedPoint;
    pub fn toString(self: FixedPoint, allocator: std.mem.Allocator) ![]u8;
};
```

### Crypto Integration

```zig
pub const EncryptedStorage = struct {
    pub fn init(allocator: std.mem.Allocator, password: []const u8) !EncryptedStorage;
    pub fn deinit(self: *EncryptedStorage) void;
    
    pub fn store(self: *EncryptedStorage, key: []const u8, data: []const u8) !void;
    pub fn retrieve(self: *EncryptedStorage, key: []const u8, allocator: std.mem.Allocator) !?[]u8;
    pub fn delete(self: *EncryptedStorage, key: []const u8) !void;
    pub fn list(self: *EncryptedStorage, allocator: std.mem.Allocator) ![][]u8;
};

pub const WalletKeypair = struct {
    algorithm: SignatureAlgorithm,
    public_key: []const u8,
    private_key: []const u8,
    derivation_path: []const u8,
    
    pub fn init(algorithm: SignatureAlgorithm, seed: []const u8, derivation_path: []const u8, allocator: std.mem.Allocator) !WalletKeypair;
    pub fn deinit(self: *WalletKeypair, allocator: std.mem.Allocator) void;
    pub fn getAddress(self: WalletKeypair, allocator: std.mem.Allocator) ![]u8;
};

pub const HDWallet = struct {
    pub fn init(mnemonic: []const u8, passphrase: ?[]const u8, allocator: std.mem.Allocator) !HDWallet;
    pub fn deinit(self: *HDWallet) void;
    pub fn deriveKeypair(self: *HDWallet, derivation_path: []const u8, algorithm: SignatureAlgorithm, allocator: std.mem.Allocator) !WalletKeypair;
    pub fn getMasterPublicKey(self: HDWallet, allocator: std.mem.Allocator) ![]u8;
};
```

---

## ZNS API

### Domain Resolution

```zig
const zns = shroud.zns;

pub const DomainRecord = struct {
    domain: []const u8,
    record_type: RecordType,
    value: []const u8,
    ttl: u32,
    signature: ?[]const u8,
};

pub const RecordType = enum {
    a,
    aaaa,
    txt,
    cname,
    mx,
    ghost,
    qid,
};

pub const UniversalResolver = struct {
    pub fn init(allocator: std.mem.Allocator) !UniversalResolver;
    pub fn deinit(self: *UniversalResolver) void;
    
    pub fn resolve(self: *UniversalResolver, domain: []const u8, record_type: RecordType) !?DomainRecord;
    pub fn resolveToIPv6(self: *UniversalResolver, domain: []const u8) !?ghostwire.ipv6.IPv6Address;
    pub fn resolveToQID(self: *UniversalResolver, domain: []const u8) !?sigil.QID;
    
    pub fn addResolver(self: *UniversalResolver, resolver: anytype) void;
    pub fn enableCache(self: *UniversalResolver, cache_path: []const u8) !void;
};

pub const ENSResolver = struct {
    pub fn init(allocator: std.mem.Allocator, rpc_url: []const u8) !ENSResolver;
    pub fn deinit(self: *ENSResolver) void;
    pub fn resolve(self: *ENSResolver, domain: []const u8, record_type: RecordType) !?DomainRecord;
};

pub const UnstoppableResolver = struct {
    pub fn init(allocator: std.mem.Allocator, api_key: []const u8) !UnstoppableResolver;
    pub fn deinit(self: *UnstoppableResolver) void;
    pub fn resolve(self: *UnstoppableResolver, domain: []const u8, record_type: RecordType) !?DomainRecord;
};

pub const GhostResolver = struct {
    pub fn init(allocator: std.mem.Allocator, ghost_rpc_url: []const u8) !GhostResolver;
    pub fn deinit(self: *GhostResolver) void;
    pub fn resolve(self: *GhostResolver, domain: []const u8, record_type: RecordType) !?DomainRecord;
    pub fn register(self: *GhostResolver, domain: []const u8, owner_keypair: sigil.RealIDKeyPair, records: []DomainRecord) !void;
};
```

### Caching

```zig
pub const Cache = struct {
    pub fn init(allocator: std.mem.Allocator, cache_path: []const u8) !Cache;
    pub fn deinit(self: *Cache) void;
    
    pub fn get(self: *Cache, key: []const u8) !?DomainRecord;
    pub fn set(self: *Cache, key: []const u8, record: DomainRecord) !void;
    pub fn delete(self: *Cache, key: []const u8) !void;
    pub fn clear(self: *Cache) !void;
    pub fn cleanup(self: *Cache) !void; // Remove expired entries
};
```

---

## ShadowCraft API

### Zero-Trust Enforcement

```zig
const shadowcraft = shroud.shadowcraft;

pub const AuthContext = struct {
    identity: ?sigil.RealIDPublicKey,
    session_id: []const u8,
    permissions: []Permission,
    expires_at: i64,
    
    pub fn init(identity: sigil.RealIDPublicKey, session_id: []const u8, allocator: std.mem.Allocator) !AuthContext;
    pub fn deinit(self: *AuthContext, allocator: std.mem.Allocator) void;
    pub fn isValid(self: AuthContext) bool;
    pub fn hasPermission(self: AuthContext, permission: Permission) bool;
    pub fn addPermission(self: *AuthContext, permission: Permission) !void;
    pub fn removePermission(self: *AuthContext, permission: Permission) void;
};

pub const Permission = struct {
    resource: []const u8,
    action: []const u8,
    conditions: []Condition,
};

pub const Condition = struct {
    field: []const u8,
    operator: Operator,
    value: []const u8,
};

pub const Operator = enum {
    equals,
    not_equals,
    greater_than,
    less_than,
    contains,
    not_contains,
    regex_match,
};

pub const PolicyEngine = struct {
    pub fn init(allocator: std.mem.Allocator) !PolicyEngine;
    pub fn deinit(self: *PolicyEngine) void;
    
    pub fn addPolicy(self: *PolicyEngine, policy: Policy) !void;
    pub fn removePolicy(self: *PolicyEngine, policy_id: []const u8) !void;
    pub fn evaluate(self: *PolicyEngine, context: AuthContext, resource: []const u8, action: []const u8) !bool;
};

pub const Policy = struct {
    id: []const u8,
    name: []const u8,
    permissions: []Permission,
    priority: u32,
    is_active: bool,
};
```

---

## Guardian API

### Multi-Signature

```zig
const guardian = shroud.guardian;

pub const MultiSigConfig = struct {
    required_signatures: u8,
    total_signers: u8,
    timeout_seconds: u32,
};

pub const MultiSigWallet = struct {
    pub fn init(allocator: std.mem.Allocator, config: MultiSigConfig, signers: []sigil.RealIDPublicKey) !MultiSigWallet;
    pub fn deinit(self: *MultiSigWallet) void;
    
    pub fn proposeTransaction(self: *MultiSigWallet, transaction: keystone.Transaction, proposer: sigil.RealIDKeyPair) ![]u8; // Returns proposal ID
    pub fn signProposal(self: *MultiSigWallet, proposal_id: []const u8, signer: sigil.RealIDKeyPair) !void;
    pub fn executeProposal(self: *MultiSigWallet, proposal_id: []const u8) !void;
    pub fn rejectProposal(self: *MultiSigWallet, proposal_id: []const u8, rejector: sigil.RealIDKeyPair) !void;
    
    pub fn getProposal(self: *MultiSigWallet, proposal_id: []const u8) !?Proposal;
    pub fn listProposals(self: *MultiSigWallet, status: ?ProposalStatus) ![]Proposal;
};

pub const Proposal = struct {
    id: []const u8,
    transaction: keystone.Transaction,
    proposer: sigil.RealIDPublicKey,
    signatures: []ProposalSignature,
    status: ProposalStatus,
    created_at: i64,
    expires_at: i64,
};

pub const ProposalSignature = struct {
    signer: sigil.RealIDPublicKey,
    signature: sigil.RealIDSignature,
    signed_at: i64,
};

pub const ProposalStatus = enum {
    pending,
    approved,
    rejected,
    executed,
    expired,
};
```

### Access Control

```zig
pub const RoleBasedAccess = struct {
    pub fn init(allocator: std.mem.Allocator) !RoleBasedAccess;
    pub fn deinit(self: *RoleBasedAccess) void;
    
    pub fn createRole(self: *RoleBasedAccess, role: Role) !void;
    pub fn assignRole(self: *RoleBasedAccess, identity: sigil.RealIDPublicKey, role_id: []const u8) !void;
    pub fn revokeRole(self: *RoleBasedAccess, identity: sigil.RealIDPublicKey, role_id: []const u8) !void;
    pub fn hasRole(self: *RoleBasedAccess, identity: sigil.RealIDPublicKey, role_id: []const u8) bool;
    pub fn checkPermission(self: *RoleBasedAccess, identity: sigil.RealIDPublicKey, resource: []const u8, action: []const u8) bool;
};

pub const Role = struct {
    id: []const u8,
    name: []const u8,
    permissions: []shadowcraft.Permission,
    parent_role: ?[]const u8,
    is_active: bool,
};
```

---

## Covenant API

### Policy Rules

```zig
const covenant = shroud.covenant;

pub const Rule = struct {
    id: []const u8,
    name: []const u8,
    condition: Condition,
    action: Action,
    priority: u32,
    is_active: bool,
};

pub const Condition = union(enum) {
    identity_match: sigil.RealIDPublicKey,
    time_range: struct { start: i64, end: i64 },
    amount_limit: struct { max_amount: keystone.FixedPoint, currency: []const u8 },
    rate_limit: struct { max_requests: u32, window_seconds: u32 },
    geo_restriction: struct { allowed_countries: [][]const u8 },
    composite: struct { operator: LogicalOperator, conditions: []Condition },
};

pub const Action = union(enum) {
    allow,
    deny,
    require_approval: struct { approvers: []sigil.RealIDPublicKey, threshold: u8 },
    log_only,
    delay: struct { delay_seconds: u32 },
};

pub const LogicalOperator = enum {
    and_op,
    or_op,
    not_op,
};

pub const PolicyEngine = struct {
    pub fn init(allocator: std.mem.Allocator) !PolicyEngine;
    pub fn deinit(self: *PolicyEngine) void;
    
    pub fn addRule(self: *PolicyEngine, rule: Rule) !void;
    pub fn removeRule(self: *PolicyEngine, rule_id: []const u8) !void;
    pub fn evaluateRules(self: *PolicyEngine, context: EvaluationContext) !PolicyDecision;
    pub fn listRules(self: *PolicyEngine, filter: ?RuleFilter) ![]Rule;
};

pub const EvaluationContext = struct {
    identity: ?sigil.RealIDPublicKey,
    resource: []const u8,
    action: []const u8,
    timestamp: i64,
    metadata: std.StringHashMap([]const u8),
};

pub const PolicyDecision = struct {
    decision: Decision,
    matched_rules: [][]const u8,
    required_approvals: ?[]sigil.RealIDPublicKey,
    delay_seconds: ?u32,
    reason: []const u8,
};

pub const Decision = enum {
    allow,
    deny,
    pending_approval,
    delayed,
};
```

---

## GWallet API

### Wallet Management

```zig
const gwallet = shroud.gwallet;

// Core types
pub const Wallet = struct {
    pub fn create(allocator: std.mem.Allocator, passphrase: []const u8, mode: WalletMode, mnemonic: ?[]const u8) !Wallet;
    pub fn fromMnemonic(allocator: std.mem.Allocator, mnemonic: []const u8, password: ?[]const u8, mode: WalletMode) !Wallet;
    pub fn deinit(self: *Wallet) void;
    pub fn lock(self: *Wallet) void;
    pub fn unlock(self: *Wallet, passphrase: []const u8) !void;
    pub fn isLocked(self: Wallet) bool;
};

pub const Account = struct {
    address: []const u8,
    public_key: []const u8,
    qid: sigil.QID,
    protocol: Protocol,
    key_type: KeyType,
    balance: keystone.FixedPoint,
};

pub const WalletMode = enum {
    public_identity,
    private_identity,
    hybrid,
    device_bound,
};

pub const Protocol = enum {
    bitcoin,
    ethereum,
    ghostchain,
    generic,
};

pub const KeyType = enum {
    ed25519,
    secp256k1,
    rsa,
};

pub const WalletError = error{
    InvalidPassphrase,
    WalletLocked,
    InsufficientFunds,
    InvalidAddress,
    SigningFailed,
    QIDGenerationFailed,
    DeviceBindingFailed,
    InvalidAccountType,
    AccountNotFound,
};

// Wallet operations
pub fn createWallet(allocator: std.mem.Allocator, passphrase: []const u8, mode: WalletMode) !Wallet;
pub fn importWallet(allocator: std.mem.Allocator, mnemonic: []const u8, password: ?[]const u8, mode: WalletMode) !Wallet;
pub fn resolveIdentity(allocator: std.mem.Allocator, domain: []const u8) ![]const u8;
pub fn startBridge(allocator: std.mem.Allocator, port: u16) !BridgeServer;
```

### Transaction Management

```zig
pub const Transaction = struct {
    id: []const u8,
    from_address: []const u8,
    to_address: []const u8,
    amount: keystone.FixedPoint,
    fee: keystone.FixedPoint,
    nonce: u64,
    gas_limit: u64,
    gas_price: keystone.FixedPoint,
    data: []const u8,
    signature: ?sigil.RealIDSignature,
    protocol: Protocol,
    status: TransactionStatus,
    
    pub fn init(allocator: std.mem.Allocator, from: []const u8, to: []const u8, amount: keystone.FixedPoint, protocol: Protocol) !Transaction;
    pub fn deinit(self: *Transaction, allocator: std.mem.Allocator) void;
    pub fn sign(self: *Transaction, private_key: sigil.RealIDPrivateKey) !void;
    pub fn verify(self: Transaction, public_key: sigil.RealIDPublicKey) bool;
    pub fn hash(self: Transaction, allocator: std.mem.Allocator) ![]u8;
};

pub const TransactionStatus = enum {
    pending,
    confirmed,
    failed,
    dropped,
};
```

### CLI Interface

```zig
pub const CLI = struct {
    pub fn init(allocator: std.mem.Allocator) CLI;
    pub fn deinit(self: *CLI) void;
    pub fn run(self: *CLI, args: [][]const u8) !void;
    
    // Command handlers
    pub fn handleGenerate(self: *CLI, args: [][]const u8) !void;
    pub fn handleImport(self: *CLI, args: [][]const u8) !void;
    pub fn handleBalance(self: *CLI, args: [][]const u8) !void;
    pub fn handleSend(self: *CLI, args: [][]const u8) !void;
    pub fn handleReceive(self: *CLI, args: [][]const u8) !void;
    pub fn handleAccounts(self: *CLI, args: [][]const u8) !void;
    pub fn handleUnlock(self: *CLI, args: [][]const u8) !void;
    pub fn handleLock(self: *CLI, args: [][]const u8) !void;
};

pub const Command = enum {
    help,
    generate,
    import,
    balance,
    send,
    receive,
    accounts,
    unlock,
    lock,
    bridge,
    version,
};
```

### Web3 Bridge

```zig
pub const Bridge = struct {
    pub fn init(allocator: std.mem.Allocator, config: BridgeConfig) !Bridge;
    pub fn deinit(self: *Bridge) void;
    pub fn start(self: *Bridge) !void;
    pub fn stop(self: *Bridge) void;
    pub fn addWallet(self: *Bridge, wallet: *Wallet) !void;
    pub fn removeWallet(self: *Bridge, wallet_id: []const u8) !void;
};

pub const BridgeConfig = struct {
    port: u16 = 8080,
    enable_cors: bool = true,
    allowed_origins: [][]const u8 = &.{},
    max_connections: u32 = 100,
    timeout_ms: u32 = 30000,
};

pub const BridgeServer = struct {
    pub fn init(allocator: std.mem.Allocator, port: u16) !BridgeServer;
    pub fn deinit(self: *BridgeServer) void;
    pub fn start(self: *BridgeServer) !void;
    pub fn stop(self: *BridgeServer) void;
};

pub const WraithBridge = struct {
    pub fn init(allocator: std.mem.Allocator, config: WraithConfig) !WraithBridge;
    pub fn deinit(self: *WraithBridge) void;
    pub fn connect(self: *WraithBridge, endpoint: []const u8) !void;
    pub fn disconnect(self: *WraithBridge) void;
    pub fn sendTransaction(self: *WraithBridge, transaction: Transaction) ![]const u8;
    pub fn getBalance(self: *WraithBridge, address: []const u8) !keystone.FixedPoint;
};

pub const WraithConfig = struct {
    endpoint: []const u8,
    timeout_ms: u32 = 30000,
    retry_attempts: u8 = 3,
    enable_encryption: bool = true,
};
```

### Identity Resolution

```zig
pub const Identity = struct {
    public_key: sigil.RealIDPublicKey,
    qid: sigil.QID,
    domain: ?[]const u8,
    
    pub fn fromPublicKey(public_key: sigil.RealIDPublicKey) Identity;
    pub fn fromDomain(allocator: std.mem.Allocator, domain: []const u8) !Identity;
    pub fn getAddress(self: Identity, protocol: Protocol, allocator: std.mem.Allocator) ![]u8;
};

pub const IdentityResolver = struct {
    pub fn init(allocator: std.mem.Allocator) IdentityResolver;
    pub fn deinit(self: *IdentityResolver) void;
    pub fn resolve(self: *IdentityResolver, domain: []const u8) ![]const u8;
    pub fn register(self: *IdentityResolver, domain: []const u8, identity: sigil.RealIDKeyPair) !void;
};
```

### FFI Interface

```zig
// C-compatible FFI types for integration with walletd/ghostd
pub const GWalletContext = extern struct {
    wallet_ptr: ?*anyopaque,
    allocator_ptr: ?*anyopaque,
    is_valid: bool,
};

pub const WalletAccount = extern struct {
    address: [64]u8,
    address_len: u32,
    public_key: [32]u8,
    qid: [16]u8,
    protocol: u32,
    key_type: u32,
};

pub const SignatureResult = extern struct {
    signature: [64]u8,
    success: bool,
};

// FFI functions
extern fn gwallet_init() GWalletContext;
extern fn gwallet_destroy(ctx: *GWalletContext) void;
extern fn gwallet_create_wallet(ctx: *GWalletContext, passphrase: [*:0]const u8, mode: u32) c_int;
extern fn gwallet_unlock_wallet(ctx: *GWalletContext, passphrase: [*:0]const u8) c_int;
extern fn gwallet_lock_wallet(ctx: *GWalletContext) c_int;
extern fn gwallet_create_account(ctx: *GWalletContext, protocol: u32, key_type: u32, account: *WalletAccount) c_int;
extern fn gwallet_sign_transaction(ctx: *GWalletContext, tx_data: [*]const u8, tx_len: usize, result: *SignatureResult) c_int;
extern fn gwallet_verify_signature(signature: [*]const u8, data: [*]const u8, data_len: usize, public_key: [*]const u8) bool;
```

---

## Error Handling

### Common Error Types

```zig
// Framework-level errors
pub const ShroudError = error{
    ModuleInitFailed,
    CryptoError,
    NetworkError,
    IdentityError,
    LedgerError,
};

// Module-specific errors
pub const CryptoError = error{
    InvalidKey,
    EncryptionFailed,
    DecryptionFailed,
    SignatureFailed,
    VerificationFailed,
};

pub const NetworkError = error{
    ConnectionFailed,
    HandshakeFailed,
    StreamError,
    ProxyError,
    ClientError,
};

pub const IdentityError = error{
    InvalidIdentity,
    ResolutionFailed,
    AuthenticationFailed,
};

pub const LedgerError = error{
    TransactionInvalid,
    InsufficientBalance,
    AccountNotFound,
    DuplicateTransaction,
};
```

### Error Handling Patterns

```zig
// Standard error handling
const result = someFunction() catch |err| switch (err) {
    ShroudError.CryptoError => {
        // Handle crypto errors
        return err;
    },
    ShroudError.NetworkError => {
        // Handle network errors
        return err;
    },
    else => return err,
};

// Error propagation
pub fn wrapperFunction() !void {
    try someFunction();
    // Error automatically propagates up
}

// Optional error handling
const maybe_result = someFunction() catch null;
if (maybe_result) |result| {
    // Use result
} else {
    // Handle error case
}
```

---

## FFI Bindings

### C/C++ Bindings

```c
// Core framework functions
const char* shroud_version(void);
int shroud_init(void);
void shroud_deinit(void);

// Identity functions
typedef struct {
    uint8_t bytes[64];
} ShroudPrivateKey;

typedef struct {
    uint8_t bytes[32];
} ShroudPublicKey;

typedef struct {
    ShroudPrivateKey private_key;
    ShroudPublicKey public_key;
} ShroudKeyPair;

typedef struct {
    uint8_t bytes[64];
} ShroudSignature;

typedef struct {
    uint8_t bytes[16];
} ShroudQID;

int shroud_generate_keypair(const char* passphrase, ShroudKeyPair* keypair);
int shroud_sign(const uint8_t* data, size_t data_len, const ShroudPrivateKey* private_key, ShroudSignature* signature);
int shroud_verify(const ShroudSignature* signature, const uint8_t* data, size_t data_len, const ShroudPublicKey* public_key);
int shroud_qid_from_pubkey(const ShroudPublicKey* public_key, ShroudQID* qid);

// Networking functions
typedef struct ShroudServer ShroudServer;

typedef void (*ShroudRequestHandler)(const char* method, const char* path, const char* body, size_t body_len, char** response, size_t* response_len);

ShroudServer* shroud_server_create(uint16_t port);
void shroud_server_destroy(ShroudServer* server);
int shroud_server_start(ShroudServer* server);
void shroud_server_stop(ShroudServer* server);
void shroud_server_add_handler(ShroudServer* server, const char* path, ShroudRequestHandler handler);

// Cryptographic functions
int shroud_encrypt_aes256_gcm(const uint8_t* key, const uint8_t* nonce, const uint8_t* plaintext, size_t plaintext_len, uint8_t* ciphertext, uint8_t* tag);
int shroud_decrypt_aes256_gcm(const uint8_t* key, const uint8_t* nonce, const uint8_t* ciphertext, size_t ciphertext_len, const uint8_t* tag, uint8_t* plaintext);

// Ledger functions
typedef struct ShroudLedger ShroudLedger;
typedef struct ShroudTransaction ShroudTransaction;

ShroudLedger* shroud_ledger_create(void);
void shroud_ledger_destroy(ShroudLedger* ledger);
uint64_t shroud_ledger_create_account(ShroudLedger* ledger, const char* name, int account_type);
ShroudTransaction* shroud_transaction_create(uint64_t id, const char* description);
void shroud_transaction_destroy(ShroudTransaction* transaction);
int shroud_ledger_post_transaction(ShroudLedger* ledger, const ShroudTransaction* transaction);
```

### Rust Bindings

```rust
// Located in archived/zquic/bindings/rust/
use shroud_sys::*;

pub struct ShroudKeyPair {
    inner: shroud_sys::ShroudKeyPair,
}

impl ShroudKeyPair {
    pub fn generate(passphrase: &str) -> Result<Self, ShroudError> {
        // FFI implementation
    }
    
    pub fn sign(&self, data: &[u8]) -> Result<ShroudSignature, ShroudError> {
        // FFI implementation
    }
}

pub struct ShroudServer {
    inner: *mut shroud_sys::ShroudServer,
}

impl ShroudServer {
    pub fn new(port: u16) -> Result<Self, ShroudError> {
        // FFI implementation
    }
    
    pub fn start(&mut self) -> Result<(), ShroudError> {
        // FFI implementation
    }
    
    pub fn add_handler<F>(&mut self, path: &str, handler: F) 
    where F: Fn(&str, &str, &[u8]) -> Result<Vec<u8>, ShroudError> {
        // FFI implementation
    }
}
```

---

## Configuration

### Build Configuration

```zig
// In build.zig
const shroud = b.addModule("shroud", .{
    .root_source_file = b.path("path/to/shroud/src/root.zig"),
    .target = target,
    .optimize = optimize,
});

// Add shroud dependency
exe.root_module.addImport("shroud", shroud);
```

### Runtime Configuration

```zig
// Configuration structures for each module
const config = struct {
    ghostcipher: ghostcipher.Config = .{},
    ghostwire: ghostwire.UnifiedServerConfig = .{},
    keystone: keystone.LedgerConfig = .{},
    zns: zns.ResolverConfig = .{},
    shadowcraft: shadowcraft.PolicyConfig = .{},
    guardian: guardian.AccessConfig = .{},
    covenant: covenant.RuleConfig = .{},
};

// Initialize with configuration
var shroud_instance = try shroud.init(allocator, config);
defer shroud_instance.deinit();
```

---

*This API reference covers the complete Shroud v1.0 framework. For detailed examples and implementation guides, see HOWTO.md.*