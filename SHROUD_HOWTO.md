# 🕸️ Shroud Implementation Guide

> Step-by-step guide for implementing the Shroud framework in your crypto projects

---

## Table of Contents

- [Quick Start](#quick-start)
- [Project Setup](#project-setup)
- [Basic Integration Examples](#basic-integration-examples)
- [Advanced Use Cases](#advanced-use-cases)
- [Crypto Project Integration](#crypto-project-integration)
- [Best Practices](#best-practices)
- [Common Patterns](#common-patterns)
- [Troubleshooting](#troubleshooting)
- [Performance Optimization](#performance-optimization)

---

## Quick Start

### 1. Add Shroud to Your Project

**Option A: Git Submodule (Recommended)**
```bash
git submodule add https://github.com/ghostkellz/shroud.git deps/shroud
git submodule update --init --recursive
```

**Option B: Clone Directly**
```bash
git clone https://github.com/your-org/shroud.git deps/shroud
```

### 2. Update Your build.zig

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add Shroud dependency
    const shroud_dep = b.dependency("shroud", .{
        .target = target,
        .optimize = optimize,
    });
    const shroud_mod = shroud_dep.module("shroud");

    // Your project executable
    const exe = b.addExecutable(.{
        .name = "your-crypto-project",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Import Shroud
    exe.root_module.addImport("shroud", shroud_mod);
    
    b.installArtifact(exe);
}
```

### 3. Basic Usage

```zig
const std = @import("std");
const shroud = @import("shroud");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Generate identity
    const identity = try shroud.sigil.realid_generate_from_passphrase("your_secure_passphrase");
    
    // Sign some data
    const data = "Hello, Shroud!";
    const signature = try shroud.sigil.realid_sign(data, identity.private_key);
    
    // Verify signature
    const is_valid = shroud.sigil.realid_verify(signature, data, identity.public_key);
    std.debug.print("Signature valid: {}\n", .{is_valid});
    
    // Get QID (IPv6 identity)
    const qid = shroud.sigil.realid_qid_from_pubkey(identity.public_key);
    std.debug.print("QID: {}\n", .{std.fmt.fmtSliceHexLower(&qid.bytes)});
}
```

---

## Project Setup

### Directory Structure

```
your-crypto-project/
├── build.zig
├── build.zig.zon
├── src/
│   ├── main.zig
│   ├── crypto/
│   │   ├── identity.zig
│   │   ├── wallet.zig
│   │   └── transactions.zig
│   ├── network/
│   │   ├── server.zig
│   │   └── client.zig
│   └── storage/
│       ├── ledger.zig
│       └── cache.zig
├── deps/
│   └── shroud/
├── examples/
├── tests/
└── README.md
```

### Dependencies Configuration (build.zig.zon)

```zig
.{
    .name = "your-crypto-project",
    .version = "0.1.0",
    .minimum_zig_version = "0.13.0",
    
    .dependencies = .{
        .shroud = .{
            .path = "deps/shroud",
        },
    },
    
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
        "examples",
        "tests",
    },
}
```

---

## Basic Integration Examples

### 1. Identity Management System

```zig
// src/crypto/identity.zig
const std = @import("std");
const shroud = @import("shroud");

pub const IdentityManager = struct {
    allocator: std.mem.Allocator,
    identities: std.StringHashMap(shroud.sigil.RealIDKeyPair),

    pub fn init(allocator: std.mem.Allocator) IdentityManager {
        return IdentityManager{
            .allocator = allocator,
            .identities = std.StringHashMap(shroud.sigil.RealIDKeyPair).init(allocator),
        };
    }

    pub fn deinit(self: *IdentityManager) void {
        self.identities.deinit();
    }

    pub fn createIdentity(self: *IdentityManager, name: []const u8, passphrase: []const u8) !void {
        const identity = try shroud.sigil.realid_generate_from_passphrase(passphrase);
        try self.identities.put(name, identity);
    }

    pub fn getIdentity(self: *IdentityManager, name: []const u8) ?shroud.sigil.RealIDKeyPair {
        return self.identities.get(name);
    }

    pub fn signMessage(self: *IdentityManager, identity_name: []const u8, message: []const u8) !shroud.sigil.RealIDSignature {
        const identity = self.identities.get(identity_name) orelse return error.IdentityNotFound;
        return try shroud.sigil.realid_sign(message, identity.private_key);
    }

    pub fn verifyMessage(self: *IdentityManager, identity_name: []const u8, message: []const u8, signature: shroud.sigil.RealIDSignature) bool {
        const identity = self.identities.get(identity_name) orelse return false;
        return shroud.sigil.realid_verify(signature, message, identity.public_key);
    }

    pub fn getQID(self: *IdentityManager, identity_name: []const u8) !shroud.sigil.QID {
        const identity = self.identities.get(identity_name) orelse return error.IdentityNotFound;
        return shroud.sigil.realid_qid_from_pubkey(identity.public_key);
    }
};

// Example usage
pub fn example() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var identity_manager = IdentityManager.init(allocator);
    defer identity_manager.deinit();

    // Create identities for different users
    try identity_manager.createIdentity("alice", "alice_secure_passphrase");
    try identity_manager.createIdentity("bob", "bob_secure_passphrase");

    // Sign and verify messages
    const message = "Transfer 100 tokens to Bob";
    const signature = try identity_manager.signMessage("alice", message);
    const is_valid = identity_manager.verifyMessage("alice", message, signature);
    
    std.debug.print("Message signed by Alice: {}\n", .{is_valid});

    // Get network identities (QIDs)
    const alice_qid = try identity_manager.getQID("alice");
    const bob_qid = try identity_manager.getQID("bob");
    
    std.debug.print("Alice QID: {}\n", .{std.fmt.fmtSliceHexLower(&alice_qid.bytes)});
    std.debug.print("Bob QID: {}\n", .{std.fmt.fmtSliceHexLower(&bob_qid.bytes)});
}
```

### 2. Secure Communication Server

```zig
// src/network/server.zig
const std = @import("std");
const shroud = @import("shroud");

pub const SecureServer = struct {
    allocator: std.mem.Allocator,
    server: shroud.ghostwire.UnifiedServer,
    identity: shroud.sigil.RealIDKeyPair,

    pub fn init(allocator: std.mem.Allocator, server_identity_passphrase: []const u8, port: u16) !SecureServer {
        // Generate server identity
        const identity = try shroud.sigil.realid_generate_from_passphrase(server_identity_passphrase);

        // Configure unified server
        const config = shroud.ghostwire.unified.UnifiedServerConfig{
            .http1_port = port,
            .http2_port = port + 1,
            .http3_port = port + 2,
            .grpc_port = port + 3,
            .websocket_port = port + 4,
            .enable_tls = true,
            .max_connections = 1000,
            .enable_ipv6 = true,
        };

        var server = try shroud.ghostwire.createUnifiedServer(allocator, config);

        // Add authenticated endpoints
        server.addHandler("/api/secure", secureHandler);
        server.addHandler("/api/identity", identityHandler);
        server.addMiddleware(authenticationMiddleware);

        return SecureServer{
            .allocator = allocator,
            .server = server,
            .identity = identity,
        };
    }

    pub fn deinit(self: *SecureServer) void {
        self.server.deinit();
    }

    pub fn start(self: *SecureServer) !void {
        std.debug.print("Starting secure server with QID: {}\n", .{
            std.fmt.fmtSliceHexLower(&shroud.sigil.realid_qid_from_pubkey(self.identity.public_key).bytes)
        });
        try self.server.start();
    }

    pub fn stop(self: *SecureServer) void {
        self.server.stop();
    }

    fn secureHandler(request: *shroud.ghostwire.UnifiedRequest, response: *shroud.ghostwire.UnifiedResponse) !void {
        // Verify client identity
        const client_identity = request.identity orelse {
            response.setStatus(401);
            response.setBody("Authentication required");
            return;
        };

        // Process secure request
        const response_data = "Secure data processed successfully";
        response.setStatus(200);
        response.setHeader("Content-Type", "text/plain");
        response.setBody(response_data);
        
        std.debug.print("Secure request processed for client: {}\n", .{
            std.fmt.fmtSliceHexLower(&client_identity.bytes)
        });
    }

    fn identityHandler(request: *shroud.ghostwire.UnifiedRequest, response: *shroud.ghostwire.UnifiedResponse) !void {
        // Return server's public identity
        const qid = shroud.sigil.realid_qid_from_pubkey(self.identity.public_key);
        
        var qid_string: [32]u8 = undefined;
        _ = std.fmt.bufPrint(&qid_string, "{}", .{std.fmt.fmtSliceHexLower(&qid.bytes)}) catch unreachable;
        
        response.setStatus(200);
        response.setHeader("Content-Type", "application/json");
        response.setBody(&qid_string);
    }

    fn authenticationMiddleware(
        request: *shroud.ghostwire.UnifiedRequest, 
        response: *shroud.ghostwire.UnifiedResponse, 
        next: shroud.ghostwire.HandlerFn
    ) !void {
        // Extract and verify client signature from headers
        const auth_header = request.headers.get("Authorization");
        if (auth_header == null) {
            try next(request, response);
            return;
        }

        // Parse authentication header and verify signature
        // Implementation depends on your authentication scheme
        
        try next(request, response);
    }
};
```

### 3. Cryptocurrency Wallet Integration

```zig
// src/crypto/wallet.zig
const std = @import("std");
const shroud = @import("shroud");

pub const CryptoWallet = struct {
    allocator: std.mem.Allocator,
    ledger: shroud.keystone.Ledger,
    identity: shroud.sigil.RealIDKeyPair,
    hd_wallet: shroud.keystone.HDWallet,
    encrypted_storage: shroud.keystone.EncryptedStorage,

    pub fn init(allocator: std.mem.Allocator, master_passphrase: []const u8, mnemonic: []const u8) !CryptoWallet {
        // Create identity from passphrase
        const identity = try shroud.sigil.realid_generate_from_passphrase(master_passphrase);
        
        // Initialize HD wallet
        const hd_wallet = try shroud.keystone.HDWallet.init(mnemonic, master_passphrase, allocator);
        
        // Create encrypted storage
        const storage = try shroud.keystone.EncryptedStorage.init(allocator, master_passphrase);
        
        // Initialize ledger
        const ledger = try shroud.keystone.Ledger.init(allocator);

        return CryptoWallet{
            .allocator = allocator,
            .ledger = ledger,
            .identity = identity,
            .hd_wallet = hd_wallet,
            .encrypted_storage = storage,
        };
    }

    pub fn deinit(self: *CryptoWallet) void {
        self.ledger.deinit();
        self.hd_wallet.deinit();
        self.encrypted_storage.deinit();
    }

    pub fn createAccount(self: *CryptoWallet, name: []const u8, currency: []const u8) !u64 {
        const account_id = try self.ledger.createAccount(name, .asset);
        
        // Store account metadata
        const metadata = try std.fmt.allocPrint(self.allocator, "{{\"currency\":\"{s}\"}}", .{currency});
        defer self.allocator.free(metadata);
        
        const storage_key = try std.fmt.allocPrint(self.allocator, "account_{d}_metadata", .{account_id});
        defer self.allocator.free(storage_key);
        
        try self.encrypted_storage.store(storage_key, metadata);
        
        return account_id;
    }

    pub fn deriveKeyForCurrency(self: *CryptoWallet, currency: []const u8, account_index: u32) !shroud.keystone.WalletKeypair {
        const derivation_path = try std.fmt.allocPrint(
            self.allocator, 
            "m/44'/0'/{d}'/0/0", 
            .{account_index}
        );
        defer self.allocator.free(derivation_path);
        
        return try self.hd_wallet.deriveKeypair(
            derivation_path, 
            .ed25519, 
            self.allocator
        );
    }

    pub fn createTransaction(
        self: *CryptoWallet, 
        from_account: u64, 
        to_account: u64, 
        amount: shroud.keystone.FixedPoint,
        description: []const u8
    ) !u64 {
        var transaction = try shroud.keystone.Transaction.init(
            self.allocator, 
            0, // Will be assigned by ledger
            description
        );
        defer transaction.deinit(self.allocator);

        // Create double-entry
        const debit_entry = shroud.keystone.JournalEntry{
            .account_id = from_account,
            .debit_amount = amount,
            .credit_amount = shroud.keystone.FixedPoint.init(0, 8),
            .description = description,
        };

        const credit_entry = shroud.keystone.JournalEntry{
            .account_id = to_account,
            .debit_amount = shroud.keystone.FixedPoint.init(0, 8),
            .credit_amount = amount,
            .description = description,
        };

        try transaction.addEntry(debit_entry);
        try transaction.addEntry(credit_entry);

        // Sign transaction with wallet identity
        const tx_data = try std.fmt.allocPrint(
            self.allocator,
            "tx:{s}:from:{d}:to:{d}:amount:{d}",
            .{ description, from_account, to_account, amount.value }
        );
        defer self.allocator.free(tx_data);

        const signature = try shroud.sigil.realid_sign(tx_data, self.identity.private_key);
        try transaction.sign(&signature.bytes);

        // Post to ledger
        try self.ledger.postTransaction(transaction);
        
        return transaction.id;
    }

    pub fn getBalance(self: *CryptoWallet, account_id: u64) !shroud.keystone.FixedPoint {
        const account = self.ledger.getAccount(account_id) orelse return error.AccountNotFound;
        return account.getBalance();
    }

    pub fn generateReceiveAddress(self: *CryptoWallet, account_id: u64) ![]u8 {
        const keypair = try self.deriveKeyForCurrency("generic", @intCast(account_id));
        defer keypair.deinit(self.allocator);
        
        return try keypair.getAddress(self.allocator);
    }
};

// Example usage
pub fn walletExample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
    
    var wallet = try CryptoWallet.init(allocator, "secure_wallet_passphrase", mnemonic);
    defer wallet.deinit();

    // Create accounts
    const btc_account = try wallet.createAccount("Bitcoin Savings", "BTC");
    const eth_account = try wallet.createAccount("Ethereum Main", "ETH");

    // Generate receive addresses
    const btc_address = try wallet.generateReceiveAddress(btc_account);
    defer allocator.free(btc_address);
    
    std.debug.print("BTC Address: {s}\n", .{btc_address});

    // Create transaction (simulated deposit)
    const amount = shroud.keystone.FixedPoint.fromFloat(1.5, 8); // 1.5 BTC
    const tx_id = try wallet.createTransaction(0, btc_account, amount, "Initial deposit");
    
    std.debug.print("Transaction created: {d}\n", .{tx_id});
    
    // Check balance
    const balance = try wallet.getBalance(btc_account);
    std.debug.print("Account balance: {}\n", .{balance.toFloat()});
}
```

### 4. GhostWallet Integration

```zig
// src/crypto/ghostwallet.zig
const std = @import("std");
const shroud = @import("shroud");

pub const GhostWalletService = struct {
    allocator: std.mem.Allocator,
    wallet: shroud.gwallet.Wallet,
    bridge: shroud.gwallet.BridgeServer,
    identity_resolver: shroud.gwallet.IdentityResolver,

    pub fn init(allocator: std.mem.Allocator, master_passphrase: []const u8, bridge_port: u16) !GhostWalletService {
        // Create GhostWallet with Sigil identity
        var wallet = try shroud.gwallet.createWallet(allocator, master_passphrase, .hybrid);
        
        // Initialize Web3 bridge for dApp integration
        var bridge = try shroud.gwallet.startBridge(allocator, bridge_port);
        
        // Setup identity resolver for domain resolution
        var identity_resolver = shroud.gwallet.IdentityResolver.init(allocator);

        return GhostWalletService{
            .allocator = allocator,
            .wallet = wallet,
            .bridge = bridge,
            .identity_resolver = identity_resolver,
        };
    }

    pub fn deinit(self: *GhostWalletService) void {
        self.wallet.deinit();
        self.bridge.deinit();
        self.identity_resolver.deinit();
    }

    pub fn createAccount(self: *GhostWalletService, protocol: shroud.gwallet.Protocol, name: []const u8) !shroud.gwallet.Account {
        // Create account with Sigil identity
        return try self.wallet.createAccount(protocol, name);
    }

    pub fn sendTransaction(
        self: *GhostWalletService,
        from_account: shroud.gwallet.Account,
        to_address: []const u8,
        amount: shroud.keystone.FixedPoint,
        protocol: shroud.gwallet.Protocol
    ) ![]const u8 {
        // Create transaction
        var transaction = try shroud.gwallet.Transaction.init(
            self.allocator,
            from_account.address,
            to_address,
            amount,
            protocol
        );
        defer transaction.deinit(self.allocator);

        // Sign with account's Sigil identity
        try transaction.sign(from_account.private_key);

        // Submit to network
        return try self.submitTransaction(transaction);
    }

    pub fn resolveWalletAddress(self: *GhostWalletService, domain: []const u8) ![]const u8 {
        // Resolve domain to wallet address using ZNS
        return try self.identity_resolver.resolve(domain);
    }

    pub fn getBalance(self: *GhostWalletService, account: shroud.gwallet.Account, token: []const u8) !shroud.keystone.FixedPoint {
        // Get balance for specific token/currency
        // This would typically query the respective blockchain
        return account.balance;
    }

    pub fn startWebBridge(self: *GhostWalletService) !void {
        // Start Web3 bridge for dApp integration
        try self.bridge.start();
        std.debug.print("GhostWallet Web3 bridge started on port {d}\n", .{self.bridge.port});
    }

    fn submitTransaction(self: *GhostWalletService, transaction: shroud.gwallet.Transaction) ![]const u8 {
        // Submit transaction to appropriate network based on protocol
        switch (transaction.protocol) {
            .bitcoin => return try self.submitBitcoinTransaction(transaction),
            .ethereum => return try self.submitEthereumTransaction(transaction),
            .ghostchain => return try self.submitGhostchainTransaction(transaction),
            .generic => return try self.submitGenericTransaction(transaction),
        }
    }

    fn submitBitcoinTransaction(self: *GhostWalletService, transaction: shroud.gwallet.Transaction) ![]const u8 {
        // Bitcoin-specific transaction submission
        const tx_hash = try transaction.hash(self.allocator);
        defer self.allocator.free(tx_hash);
        
        std.debug.print("Submitting Bitcoin transaction: {s}\n", .{std.fmt.fmtSliceHexLower(tx_hash)});
        return try self.allocator.dupe(u8, tx_hash);
    }

    fn submitEthereumTransaction(self: *GhostWalletService, transaction: shroud.gwallet.Transaction) ![]const u8 {
        // Ethereum-specific transaction submission
        const tx_hash = try transaction.hash(self.allocator);
        defer self.allocator.free(tx_hash);
        
        std.debug.print("Submitting Ethereum transaction: {s}\n", .{std.fmt.fmtSliceHexLower(tx_hash)});
        return try self.allocator.dupe(u8, tx_hash);
    }

    fn submitGhostchainTransaction(self: *GhostWalletService, transaction: shroud.gwallet.Transaction) ![]const u8 {
        // Ghostchain-specific transaction submission with enhanced privacy
        const tx_hash = try transaction.hash(self.allocator);
        defer self.allocator.free(tx_hash);
        
        std.debug.print("Submitting Ghostchain transaction: {s}\n", .{std.fmt.fmtSliceHexLower(tx_hash)});
        return try self.allocator.dupe(u8, tx_hash);
    }

    fn submitGenericTransaction(self: *GhostWalletService, transaction: shroud.gwallet.Transaction) ![]const u8 {
        // Generic transaction submission
        const tx_hash = try transaction.hash(self.allocator);
        defer self.allocator.free(tx_hash);
        
        std.debug.print("Submitting generic transaction: {s}\n", .{std.fmt.fmtSliceHexLower(tx_hash)});
        return try self.allocator.dupe(u8, tx_hash);
    }
};

// Example usage
pub fn ghostWalletExample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ghost_wallet = try GhostWalletService.init(
        allocator,
        "secure_master_passphrase_for_wallet",
        8080
    );
    defer ghost_wallet.deinit();

    // Create accounts for different protocols
    const btc_account = try ghost_wallet.createAccount(.bitcoin, "Bitcoin Main");
    const eth_account = try ghost_wallet.createAccount(.ethereum, "Ethereum Main");
    const ghost_account = try ghost_wallet.createAccount(.ghostchain, "Ghost Privacy");

    std.debug.print("Created accounts:\n");
    std.debug.print("Bitcoin: {s}\n", .{btc_account.address});
    std.debug.print("Ethereum: {s}\n", .{eth_account.address});
    std.debug.print("Ghostchain: {s}\n", .{ghost_account.address});

    // Send transaction using domain resolution
    const recipient_address = try ghost_wallet.resolveWalletAddress("alice.ghost");
    defer allocator.free(recipient_address);

    const amount = shroud.keystone.FixedPoint.fromFloat(1.5, 8); // 1.5 tokens
    const tx_hash = try ghost_wallet.sendTransaction(
        ghost_account,
        recipient_address,
        amount,
        .ghostchain
    );
    defer allocator.free(tx_hash);

    std.debug.print("Transaction sent: {s}\n", .{tx_hash});

    // Start Web3 bridge for dApp integration
    try ghost_wallet.startWebBridge();
    
    // Check balances
    const btc_balance = try ghost_wallet.getBalance(btc_account, "BTC");
    const eth_balance = try ghost_wallet.getBalance(eth_account, "ETH");
    const ghost_balance = try ghost_wallet.getBalance(ghost_account, "GHOST");

    std.debug.print("Balances:\n");
    std.debug.print("Bitcoin: {}\n", .{btc_balance.toFloat()});
    std.debug.print("Ethereum: {}\n", .{eth_balance.toFloat()});
    std.debug.print("Ghostchain: {}\n", .{ghost_balance.toFloat()});
}
```

### 5. Decentralized Domain Resolution

```zig
// src/network/domain_resolver.zig
const std = @import("std");
const shroud = @import("shroud");

pub const DomainService = struct {
    allocator: std.mem.Allocator,
    resolver: shroud.zns.resolver.UniversalResolver,
    cache: shroud.zns.Cache,
    server_identity: shroud.sigil.RealIDKeyPair,

    pub fn init(allocator: std.mem.Allocator, cache_path: []const u8, identity_passphrase: []const u8) !DomainService {
        var resolver = try shroud.zns.resolver.UniversalResolver.init(allocator);
        
        // Enable caching
        try resolver.enableCache(cache_path);
        
        // Add resolvers for different domain types
        const ens_resolver = try shroud.zns.resolver.ENSResolver.init(allocator, "https://mainnet.infura.io/v3/YOUR_API_KEY");
        const unstoppable_resolver = try shroud.zns.resolver.UnstoppableResolver.init(allocator, "YOUR_UNSTOPPABLE_API_KEY");
        const ghost_resolver = try shroud.zns.resolver.GhostResolver.init(allocator, "https://ghost-rpc.example.com");
        
        resolver.addResolver(ens_resolver);
        resolver.addResolver(unstoppable_resolver);
        resolver.addResolver(ghost_resolver);

        const cache = try shroud.zns.Cache.init(allocator, cache_path);
        const identity = try shroud.sigil.realid_generate_from_passphrase(identity_passphrase);

        return DomainService{
            .allocator = allocator,
            .resolver = resolver,
            .cache = cache,
            .server_identity = identity,
        };
    }

    pub fn deinit(self: *DomainService) void {
        self.resolver.deinit();
        self.cache.deinit();
    }

    pub fn resolveDomain(self: *DomainService, domain: []const u8) !?shroud.ghostwire.ipv6.IPv6Address {
        // Try cache first
        const cache_key = try std.fmt.allocPrint(self.allocator, "ipv6:{s}", .{domain});
        defer self.allocator.free(cache_key);
        
        if (try self.cache.get(cache_key)) |cached_record| {
            defer self.allocator.free(cached_record.value);
            return try shroud.ghostwire.ipv6.IPv6Address.fromString(cached_record.value);
        }

        // Resolve via universal resolver
        const ipv6_addr = try self.resolver.resolveToIPv6(domain);
        
        if (ipv6_addr) |addr| {
            // Cache the result
            const addr_string = try addr.toString(self.allocator);
            defer self.allocator.free(addr_string);
            
            const record = shroud.zns.DomainRecord{
                .domain = domain,
                .record_type = .aaaa,
                .value = addr_string,
                .ttl = 3600,
                .signature = null,
            };
            
            try self.cache.set(cache_key, record);
        }

        return ipv6_addr;
    }

    pub fn resolveToQID(self: *DomainService, domain: []const u8) !?shroud.sigil.QID {
        return try self.resolver.resolveToQID(domain);
    }

    pub fn registerGhostDomain(
        self: *DomainService, 
        domain: []const u8, 
        owner_identity: shroud.sigil.RealIDKeyPair,
        ipv6_address: shroud.ghostwire.ipv6.IPv6Address
    ) !void {
        const addr_string = try ipv6_address.toString(self.allocator);
        defer self.allocator.free(addr_string);
        
        const records = [_]shroud.zns.DomainRecord{
            .{
                .domain = domain,
                .record_type = .aaaa,
                .value = addr_string,
                .ttl = 3600,
                .signature = null,
            },
            .{
                .domain = domain,
                .record_type = .qid,
                .value = &shroud.sigil.realid_qid_from_pubkey(owner_identity.public_key).bytes,
                .ttl = 86400,
                .signature = null,
            },
        };

        // This would typically interact with a Ghost blockchain or registry
        const ghost_resolver = self.resolver.getGhostResolver() orelse return error.GhostResolverNotAvailable;
        try ghost_resolver.register(domain, owner_identity, &records);
    }
};

// Example usage
pub fn domainExample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var domain_service = try DomainService.init(
        allocator, 
        "/tmp/domain_cache.db", 
        "domain_service_identity"
    );
    defer domain_service.deinit();

    // Resolve traditional domains
    if (try domain_service.resolveDomain("example.eth")) |ipv6_addr| {
        const addr_string = try ipv6_addr.toString(allocator);
        defer allocator.free(addr_string);
        std.debug.print("example.eth resolves to: {s}\n", .{addr_string});
    }

    // Resolve to QID
    if (try domain_service.resolveToQID("alice.ghost")) |qid| {
        std.debug.print("alice.ghost QID: {}\n", .{std.fmt.fmtSliceHexLower(&qid.bytes)});
    }

    // Register a new ghost domain
    const owner_identity = try shroud.sigil.realid_generate_from_passphrase("alice_domain_owner");
    const server_addr = try shroud.ghostwire.ipv6.IPv6Address.fromString("2001:db8::1");
    
    try domain_service.registerGhostDomain("myproject.ghost", owner_identity, server_addr);
    std.debug.print("Registered myproject.ghost\n");
}
```

---

## Advanced Use Cases

### 1. Multi-Signature Treasury

```zig
// src/crypto/treasury.zig
const std = @import("std");
const shroud = @import("shroud");

pub const Treasury = struct {
    allocator: std.mem.Allocator,
    multisig_wallet: shroud.guardian.MultiSigWallet,
    ledger: shroud.keystone.Ledger,
    treasury_account: u64,
    signers: []shroud.sigil.RealIDKeyPair,

    pub fn init(
        allocator: std.mem.Allocator,
        required_sigs: u8,
        signer_passphrases: []const []const u8
    ) !Treasury {
        // Generate signer identities
        const signers = try allocator.alloc(shroud.sigil.RealIDKeyPair, signer_passphrases.len);
        var signer_pubkeys = try allocator.alloc(shroud.sigil.RealIDPublicKey, signer_passphrases.len);
        defer allocator.free(signer_pubkeys);

        for (signer_passphrases, 0..) |passphrase, i| {
            signers[i] = try shroud.sigil.realid_generate_from_passphrase(passphrase);
            signer_pubkeys[i] = signers[i].public_key;
        }

        // Create multisig configuration
        const multisig_config = shroud.guardian.MultiSigConfig{
            .required_signatures = required_sigs,
            .total_signers = @intCast(signers.len),
            .timeout_seconds = 3600, // 1 hour timeout
        };

        const multisig_wallet = try shroud.guardian.MultiSigWallet.init(
            allocator,
            multisig_config,
            signer_pubkeys
        );

        // Initialize ledger and create treasury account
        var ledger = try shroud.keystone.Ledger.init(allocator);
        const treasury_account = try ledger.createAccount("Treasury", .asset);

        return Treasury{
            .allocator = allocator,
            .multisig_wallet = multisig_wallet,
            .ledger = ledger,
            .treasury_account = treasury_account,
            .signers = signers,
        };
    }

    pub fn deinit(self: *Treasury) void {
        self.multisig_wallet.deinit();
        self.ledger.deinit();
        self.allocator.free(self.signers);
    }

    pub fn proposeWithdrawal(
        self: *Treasury,
        proposer_index: usize,
        to_account: u64,
        amount: shroud.keystone.FixedPoint,
        description: []const u8
    ) ![]u8 {
        // Create withdrawal transaction
        var transaction = try shroud.keystone.Transaction.init(
            self.allocator,
            0,
            description
        );

        const withdrawal_entry = shroud.keystone.JournalEntry{
            .account_id = self.treasury_account,
            .debit_amount = amount,
            .credit_amount = shroud.keystone.FixedPoint.init(0, 8),
            .description = description,
        };

        const destination_entry = shroud.keystone.JournalEntry{
            .account_id = to_account,
            .debit_amount = shroud.keystone.FixedPoint.init(0, 8),
            .credit_amount = amount,
            .description = description,
        };

        try transaction.addEntry(withdrawal_entry);
        try transaction.addEntry(destination_entry);

        // Propose transaction for multisig approval
        const proposal_id = try self.multisig_wallet.proposeTransaction(
            transaction,
            self.signers[proposer_index]
        );

        std.debug.print("Withdrawal proposal created: {s}\n", .{proposal_id});
        return try self.allocator.dupe(u8, proposal_id);
    }

    pub fn signProposal(self: *Treasury, proposal_id: []const u8, signer_index: usize) !void {
        try self.multisig_wallet.signProposal(proposal_id, self.signers[signer_index]);
        std.debug.print("Proposal {s} signed by signer {d}\n", .{ proposal_id, signer_index });
    }

    pub fn executeProposal(self: *Treasury, proposal_id: []const u8) !void {
        try self.multisig_wallet.executeProposal(proposal_id);
        
        // Get the executed transaction and post to ledger
        const proposal = try self.multisig_wallet.getProposal(proposal_id);
        if (proposal) |p| {
            try self.ledger.postTransaction(p.transaction);
            std.debug.print("Proposal {s} executed and posted to ledger\n", .{proposal_id});
        }
    }

    pub fn getTreasuryBalance(self: *Treasury) !shroud.keystone.FixedPoint {
        const account = self.ledger.getAccount(self.treasury_account) orelse return error.AccountNotFound;
        return account.getBalance();
    }

    pub fn listPendingProposals(self: *Treasury) ![]shroud.guardian.Proposal {
        return try self.multisig_wallet.listProposals(.pending);
    }
};

// Example usage
pub fn treasuryExample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create treasury with 3 signers, requiring 2 signatures
    const signer_passphrases = [_][]const u8{
        "treasury_signer_alice",
        "treasury_signer_bob", 
        "treasury_signer_charlie"
    };

    var treasury = try Treasury.init(allocator, 2, &signer_passphrases);
    defer treasury.deinit();

    // Create a destination account
    const recipient_account = try treasury.ledger.createAccount("Recipient", .asset);

    // Propose withdrawal
    const amount = shroud.keystone.FixedPoint.fromFloat(1000.0, 8);
    const proposal_id = try treasury.proposeWithdrawal(
        0, // Alice proposes
        recipient_account,
        amount,
        "Monthly development grant"
    );
    defer allocator.free(proposal_id);

    // Sign with required signatures
    try treasury.signProposal(proposal_id, 1); // Bob signs
    try treasury.signProposal(proposal_id, 2); // Charlie signs

    // Execute the proposal
    try treasury.executeProposal(proposal_id);

    // Check results
    const balance = try treasury.getTreasuryBalance();
    std.debug.print("Treasury balance after withdrawal: {}\n", .{balance.toFloat()});
}
```

### 2. Cross-Chain Bridge Service

```zig
// src/network/bridge.zig
const std = @import("std");
const shroud = @import("shroud");

pub const CrossChainBridge = struct {
    allocator: std.mem.Allocator,
    server: shroud.ghostwire.UnifiedServer,
    identity: shroud.sigil.RealIDKeyPair,
    supported_chains: std.StringHashMap(ChainConfig),
    pending_transfers: std.StringHashMap(BridgeTransfer),
    validator_set: []shroud.sigil.RealIDPublicKey,

    const ChainConfig = struct {
        name: []const u8,
        rpc_url: []const u8,
        contract_address: []const u8,
        confirmation_blocks: u32,
    };

    const BridgeTransfer = struct {
        id: []const u8,
        from_chain: []const u8,
        to_chain: []const u8,
        from_address: []const u8,
        to_address: []const u8,
        amount: shroud.keystone.FixedPoint,
        status: TransferStatus,
        created_at: i64,
        confirmations: u32,
        signatures: []shroud.sigil.RealIDSignature,
    };

    const TransferStatus = enum {
        pending,
        confirmed,
        validated,
        executed,
        failed,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        bridge_passphrase: []const u8,
        server_port: u16,
        validator_passphrases: []const []const u8
    ) !CrossChainBridge {
        const identity = try shroud.sigil.realid_generate_from_passphrase(bridge_passphrase);
        
        // Generate validator identities
        const validators = try allocator.alloc(shroud.sigil.RealIDPublicKey, validator_passphrases.len);
        for (validator_passphrases, 0..) |passphrase, i| {
            const validator_identity = try shroud.sigil.realid_generate_from_passphrase(passphrase);
            validators[i] = validator_identity.public_key;
        }

        // Setup server
        const server_config = shroud.ghostwire.unified.UnifiedServerConfig{
            .http1_port = server_port,
            .http2_port = server_port + 1,
            .http3_port = server_port + 2,
            .grpc_port = server_port + 3,
        };

        var server = try shroud.ghostwire.createUnifiedServer(allocator, server_config);
        
        // Setup bridge endpoints
        server.addHandler("/bridge/transfer", transferHandler);
        server.addHandler("/bridge/status", statusHandler);
        server.addHandler("/bridge/validate", validateHandler);

        return CrossChainBridge{
            .allocator = allocator,
            .server = server,
            .identity = identity,
            .supported_chains = std.StringHashMap(ChainConfig).init(allocator),
            .pending_transfers = std.StringHashMap(BridgeTransfer).init(allocator),
            .validator_set = validators,
        };
    }

    pub fn deinit(self: *CrossChainBridge) void {
        self.server.deinit();
        self.supported_chains.deinit();
        self.pending_transfers.deinit();
        self.allocator.free(self.validator_set);
    }

    pub fn addSupportedChain(self: *CrossChainBridge, chain_config: ChainConfig) !void {
        try self.supported_chains.put(chain_config.name, chain_config);
    }

    pub fn start(self: *CrossChainBridge) !void {
        std.debug.print("Starting cross-chain bridge service...\n");
        try self.server.start();
    }

    pub fn initiateBridgeTransfer(
        self: *CrossChainBridge,
        from_chain: []const u8,
        to_chain: []const u8,
        from_address: []const u8,
        to_address: []const u8,
        amount: shroud.keystone.FixedPoint
    ) ![]u8 {
        // Verify chains are supported
        if (!self.supported_chains.contains(from_chain) or !self.supported_chains.contains(to_chain)) {
            return error.UnsupportedChain;
        }

        // Generate transfer ID
        const transfer_id = try self.generateTransferId();
        
        const transfer = BridgeTransfer{
            .id = try self.allocator.dupe(u8, transfer_id),
            .from_chain = try self.allocator.dupe(u8, from_chain),
            .to_chain = try self.allocator.dupe(u8, to_chain),
            .from_address = try self.allocator.dupe(u8, from_address),
            .to_address = try self.allocator.dupe(u8, to_address),
            .amount = amount,
            .status = .pending,
            .created_at = std.time.timestamp(),
            .confirmations = 0,
            .signatures = try self.allocator.alloc(shroud.sigil.RealIDSignature, 0),
        };

        try self.pending_transfers.put(transfer_id, transfer);
        
        std.debug.print("Bridge transfer initiated: {s}\n", .{transfer_id});
        return try self.allocator.dupe(u8, transfer_id);
    }

    fn generateTransferId(self: *CrossChainBridge) ![]u8 {
        const timestamp = std.time.timestamp();
        const random_bytes = try self.allocator.alloc(u8, 16);
        defer self.allocator.free(random_bytes);
        
        std.crypto.random.bytes(random_bytes);
        
        return try std.fmt.allocPrint(
            self.allocator,
            "{d}_{s}",
            .{ timestamp, std.fmt.fmtSliceHexLower(random_bytes) }
        );
    }

    fn transferHandler(request: *shroud.ghostwire.UnifiedRequest, response: *shroud.ghostwire.UnifiedResponse) !void {
        // Parse transfer request and initiate bridge transfer
        // Implementation would parse JSON request body
        response.setStatus(200);
        response.setBody("Transfer initiated");
    }

    fn statusHandler(request: *shroud.ghostwire.UnifiedRequest, response: *shroud.ghostwire.UnifiedResponse) !void {
        // Return transfer status
        response.setStatus(200);
        response.setBody("Status endpoint");
    }

    fn validateHandler(request: *shroud.ghostwire.UnifiedRequest, response: *shroud.ghostwire.UnifiedResponse) !void {
        // Validator endpoint for signing transfers
        response.setStatus(200);
        response.setBody("Validation endpoint");
    }
};
```

---

## Crypto Project Integration

### Integration Checklist

1. **Identity Layer**
   - [ ] Generate project-specific identities
   - [ ] Implement signature verification
   - [ ] Setup QID-based networking
   - [ ] Configure device fingerprinting

2. **Networking Layer**
   - [ ] Setup unified server for API endpoints
   - [ ] Configure gRPC services for high-performance operations
   - [ ] Implement WebSocket for real-time updates
   - [ ] Setup IPv6 for future-proof networking

3. **Cryptographic Layer**
   - [ ] Choose appropriate algorithms for your use case
   - [ ] Implement message signing for all transactions
   - [ ] Setup encrypted storage for sensitive data
   - [ ] Plan for post-quantum migration

4. **Ledger Layer**
   - [ ] Design account hierarchy
   - [ ] Implement transaction types
   - [ ] Setup audit trails
   - [ ] Configure backup and recovery

5. **Domain Layer**
   - [ ] Register project domains (.ghost, .crypto, etc.)
   - [ ] Setup domain resolution
   - [ ] Configure caching
   - [ ] Plan for domain governance

6. **Wallet Layer (GhostWallet)**
   - [ ] Initialize wallet with Sigil identity
   - [ ] Create accounts for required protocols
   - [ ] Setup Web3 bridge for dApp integration
   - [ ] Configure transaction signing
   - [ ] Implement domain-based address resolution

### Common Integration Patterns

#### Pattern 1: DeFi Protocol

```zig
const DeFiProtocol = struct {
    identity_manager: IdentityManager,
    treasury: Treasury,
    domain_service: DomainService,
    bridge_service: CrossChainBridge,
    wallet_service: GhostWalletService,
    
    pub fn init(allocator: std.mem.Allocator, config: DeFiConfig) !DeFiProtocol {
        // Initialize all Shroud components
        const identity_manager = IdentityManager.init(allocator);
        const treasury = try Treasury.init(allocator, config.multisig_threshold, config.signer_passphrases);
        const domain_service = try DomainService.init(allocator, config.cache_path, config.domain_passphrase);
        const bridge_service = try CrossChainBridge.init(allocator, config.bridge_passphrase, config.bridge_port, config.validator_passphrases);
        const wallet_service = try GhostWalletService.init(allocator, config.wallet_passphrase, config.wallet_bridge_port);
        
        return DeFiProtocol{
            .identity_manager = identity_manager,
            .treasury = treasury,
            .domain_service = domain_service,
            .bridge_service = bridge_service,
            .wallet_service = wallet_service,
        };
    }
    
    pub fn deployLiquidityPool(self: *DeFiProtocol, token_a: []const u8, token_b: []const u8) !void {
        // Implementation using Shroud components
    }
};
```

#### Pattern 2: NFT Marketplace

```zig
const NFTMarketplace = struct {
    server: shroud.ghostwire.UnifiedServer,
    identity_registry: IdentityManager,
    asset_ledger: shroud.keystone.Ledger,
    domain_resolver: DomainService,
    
    pub fn mintNFT(self: *NFTMarketplace, creator: shroud.sigil.RealIDKeyPair, metadata: []const u8) !u64 {
        // Create NFT account in ledger
        const nft_account = try self.asset_ledger.createAccount("NFT", .asset);
        
        // Sign metadata with creator identity
        const signature = try shroud.sigil.realid_sign(metadata, creator.private_key);
        
        // Store in encrypted storage with signature
        // Return NFT ID
        return nft_account;
    }
};
```

#### Pattern 3: Gaming Platform

```zig
const GamePlatform = struct {
    player_identities: IdentityManager,
    game_server: shroud.ghostwire.UnifiedServer,
    asset_system: shroud.keystone.Ledger,
    matchmaking: shroud.ghostwire.websocket.WebSocketServer,
    
    pub fn authenticatePlayer(self: *GamePlatform, player_id: []const u8, challenge: []const u8, signature: shroud.sigil.RealIDSignature) !bool {
        const identity = self.player_identities.getIdentity(player_id) orelse return false;
        return shroud.sigil.realid_verify(signature, challenge, identity.public_key);
    }
    
    pub fn transferGameAsset(self: *GamePlatform, from_player: []const u8, to_player: []const u8, asset_id: u64) !void {
        // Use Shroud's ledger for secure asset transfers
    }
};
```

---

## Best Practices

### 1. Security Best Practices

```zig
// Always validate inputs
pub fn secureFunction(input: []const u8) !void {
    if (input.len == 0 or input.len > MAX_INPUT_SIZE) {
        return error.InvalidInput;
    }
    
    // Sanitize input before processing
    for (input) |byte| {
        if (byte < 32 or byte > 126) {
            return error.InvalidCharacter;
        }
    }
}

// Use secure random for sensitive operations
pub fn generateSecureToken(allocator: std.mem.Allocator) ![]u8 {
    const token = try allocator.alloc(u8, 32);
    std.crypto.random.bytes(token);
    return token;
}

// Always verify signatures before processing
pub fn processSignedMessage(message: []const u8, signature: shroud.sigil.RealIDSignature, public_key: shroud.sigil.RealIDPublicKey) !void {
    if (!shroud.sigil.realid_verify(signature, message, public_key)) {
        return error.InvalidSignature;
    }
    
    // Process message only after verification
}
```

### 2. Performance Best Practices

```zig
// Use arena allocators for temporary operations
pub fn batchOperation(allocator: std.mem.Allocator, items: []const Item) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const temp_allocator = arena.allocator();
    
    // All temporary allocations will be freed together
    for (items) |item| {
        const processed = try processItem(temp_allocator, item);
        // Use processed data
    }
}

// Batch signature operations when possible
pub fn verifyBatch(messages: []const []const u8, signatures: []const shroud.sigil.RealIDSignature, public_key: shroud.sigil.RealIDPublicKey) ![]bool {
    const results = try allocator.alloc(bool, messages.len);
    
    for (messages, signatures, 0..) |message, signature, i| {
        results[i] = shroud.sigil.realid_verify(signature, message, public_key);
    }
    
    return results;
}
```

### 3. Error Handling Best Practices

```zig
// Define domain-specific error types
const ProjectError = error{
    InvalidConfiguration,
    ServiceUnavailable,
    InsufficientPermissions,
    DataCorruption,
} || shroud.ShroudError;

// Provide meaningful error context
pub fn initializeService(config: Config) ProjectError!Service {
    const identity = shroud.sigil.realid_generate_from_passphrase(config.passphrase) catch |err| switch (err) {
        shroud.sigil.RealIDError.InvalidPassphrase => return ProjectError.InvalidConfiguration,
        else => return err,
    };
    
    const server = shroud.ghostwire.createUnifiedServer(allocator, config.server) catch |err| switch (err) {
        shroud.ghostwire.TransportError.NetworkError => return ProjectError.ServiceUnavailable,
        else => return err,
    };
    
    return Service{ .identity = identity, .server = server };
}
```

### 4. Configuration Management

```zig
// Use structured configuration
const ProjectConfig = struct {
    identity: struct {
        passphrase: []const u8,
        enable_device_fingerprinting: bool = true,
    },
    
    network: struct {
        server_port: u16 = 8080,
        enable_tls: bool = true,
        cert_path: ?[]const u8 = null,
        key_path: ?[]const u8 = null,
    },
    
    storage: struct {
        cache_path: []const u8 = "/tmp/cache",
        encryption_key: []const u8,
    },
    
    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !ProjectConfig {
        // Load and parse configuration file
    }
    
    pub fn validate(self: ProjectConfig) !void {
        if (self.identity.passphrase.len < 12) {
            return error.WeakPassphrase;
        }
        
        if (self.network.enable_tls and (self.network.cert_path == null or self.network.key_path == null)) {
            return error.TLSConfigIncomplete;
        }
    }
};
```

---

## Common Patterns

### 1. Request/Response with Authentication

```zig
const AuthenticatedHandler = struct {
    identity_manager: *IdentityManager,
    
    pub fn handle(self: *AuthenticatedHandler, request: *shroud.ghostwire.UnifiedRequest, response: *shroud.ghostwire.UnifiedResponse) !void {
        // Extract authentication from headers
        const auth_header = request.headers.get("Authorization") orelse {
            response.setStatus(401);
            response.setBody("Missing authentication");
            return;
        };
        
        // Parse: "Bearer <base64_encoded_signature>"
        if (!std.mem.startsWith(u8, auth_header, "Bearer ")) {
            response.setStatus(401);
            response.setBody("Invalid authentication format");
            return;
        }
        
        const signature_b64 = auth_header[7..];
        var signature_bytes: [64]u8 = undefined;
        _ = try std.base64.standard.Decoder.decode(&signature_bytes, signature_b64);
        
        const signature = shroud.sigil.RealIDSignature{ .bytes = signature_bytes };
        
        // Verify signature against request data
        const request_data = try std.fmt.allocPrint(request.allocator, "{s}:{s}", .{ request.method, request.path });
        defer request.allocator.free(request_data);
        
        const public_key = request.identity orelse {
            response.setStatus(401);
            response.setBody("Missing identity");
            return;
        };
        
        if (!shroud.sigil.realid_verify(signature, request_data, public_key)) {
            response.setStatus(401);
            response.setBody("Invalid signature");
            return;
        }
        
        // Process authenticated request
        response.setStatus(200);
        response.setBody("Authenticated request processed");
    }
};
```

### 2. Async Event Processing

```zig
const EventProcessor = struct {
    allocator: std.mem.Allocator,
    event_queue: std.atomic.Queue(Event),
    worker_threads: []std.Thread,
    should_stop: std.atomic.Atomic(bool),
    
    const Event = struct {
        type: EventType,
        data: []const u8,
        signature: shroud.sigil.RealIDSignature,
        sender: shroud.sigil.RealIDPublicKey,
    };
    
    const EventType = enum {
        transaction,
        message,
        system_update,
    };
    
    pub fn init(allocator: std.mem.Allocator, num_workers: u32) !EventProcessor {
        const event_queue = std.atomic.Queue(Event).init();
        const worker_threads = try allocator.alloc(std.Thread, num_workers);
        
        var processor = EventProcessor{
            .allocator = allocator,
            .event_queue = event_queue,
            .worker_threads = worker_threads,
            .should_stop = std.atomic.Atomic(bool).init(false),
        };
        
        // Start worker threads
        for (worker_threads, 0..) |*thread, i| {
            thread.* = try std.Thread.spawn(.{}, workerLoop, .{ &processor, i });
        }
        
        return processor;
    }
    
    pub fn deinit(self: *EventProcessor) void {
        self.should_stop.store(true, .SeqCst);
        
        // Wait for workers to finish
        for (self.worker_threads) |thread| {
            thread.join();
        }
        
        self.allocator.free(self.worker_threads);
    }
    
    pub fn submitEvent(self: *EventProcessor, event: Event) void {
        self.event_queue.put(event);
    }
    
    fn workerLoop(self: *EventProcessor, worker_id: usize) void {
        while (!self.should_stop.load(.SeqCst)) {
            if (self.event_queue.get()) |event| {
                self.processEvent(event, worker_id) catch |err| {
                    std.debug.print("Worker {d} error processing event: {}\n", .{ worker_id, err });
                };
            } else {
                // No events, sleep briefly
                std.time.sleep(1_000_000); // 1ms
            }
        }
    }
    
    fn processEvent(self: *EventProcessor, event: Event, worker_id: usize) !void {
        // Verify event signature
        if (!shroud.sigil.realid_verify(event.signature, event.data, event.sender)) {
            std.debug.print("Invalid event signature from worker {d}\n", .{worker_id});
            return;
        }
        
        // Process based on event type
        switch (event.type) {
            .transaction => try self.processTransaction(event),
            .message => try self.processMessage(event),
            .system_update => try self.processSystemUpdate(event),
        }
    }
    
    fn processTransaction(self: *EventProcessor, event: Event) !void {
        // Process transaction event
        std.debug.print("Processing transaction: {s}\n", .{event.data});
    }
    
    fn processMessage(self: *EventProcessor, event: Event) !void {
        // Process message event
        std.debug.print("Processing message: {s}\n", .{event.data});
    }
    
    fn processSystemUpdate(self: *EventProcessor, event: Event) !void {
        // Process system update event
        std.debug.print("Processing system update: {s}\n", .{event.data});
    }
};
```

### 3. Configuration-Driven Service Discovery

```zig
const ServiceRegistry = struct {
    allocator: std.mem.Allocator,
    domain_resolver: *DomainService,
    services: std.StringHashMap(ServiceInfo),
    
    const ServiceInfo = struct {
        name: []const u8,
        domain: []const u8,
        qid: shroud.sigil.QID,
        endpoints: []EndpointInfo,
        health_status: HealthStatus,
        last_check: i64,
    };
    
    const EndpointInfo = struct {
        protocol: []const u8, // "http", "grpc", "websocket"
        address: shroud.ghostwire.ipv6.IPv6Address,
        port: u16,
        path: ?[]const u8,
    };
    
    const HealthStatus = enum {
        healthy,
        degraded,
        unhealthy,
        unknown,
    };
    
    pub fn init(allocator: std.mem.Allocator, domain_resolver: *DomainService) ServiceRegistry {
        return ServiceRegistry{
            .allocator = allocator,
            .domain_resolver = domain_resolver,
            .services = std.StringHashMap(ServiceInfo).init(allocator),
        };
    }
    
    pub fn deinit(self: *ServiceRegistry) void {
        self.services.deinit();
    }
    
    pub fn discoverService(self: *ServiceRegistry, service_name: []const u8) !?ServiceInfo {
        // Check cache first
        if (self.services.get(service_name)) |cached_service| {
            if (std.time.timestamp() - cached_service.last_check < 300) { // 5 minutes
                return cached_service;
            }
        }
        
        // Resolve service domain
        const service_domain = try std.fmt.allocPrint(
            self.allocator,
            "{s}.services.ghost",
            .{service_name}
        );
        defer self.allocator.free(service_domain);
        
        const service_addr = try self.domain_resolver.resolveDomain(service_domain);
        const service_qid = try self.domain_resolver.resolveToQID(service_domain);
        
        if (service_addr == null or service_qid == null) {
            return null;
        }
        
        // Create service info
        const endpoints = try self.allocator.alloc(EndpointInfo, 3);
        endpoints[0] = EndpointInfo{
            .protocol = "http",
            .address = service_addr.?,
            .port = 8080,
            .path = "/api",
        };
        endpoints[1] = EndpointInfo{
            .protocol = "grpc",
            .address = service_addr.?,
            .port = 50051,
            .path = null,
        };
        endpoints[2] = EndpointInfo{
            .protocol = "websocket",
            .address = service_addr.?,
            .port = 8765,
            .path = "/ws",
        };
        
        const service_info = ServiceInfo{
            .name = try self.allocator.dupe(u8, service_name),
            .domain = try self.allocator.dupe(u8, service_domain),
            .qid = service_qid.?,
            .endpoints = endpoints,
            .health_status = .unknown,
            .last_check = std.time.timestamp(),
        };
        
        // Cache and return
        try self.services.put(service_name, service_info);
        return service_info;
    }
    
    pub fn checkHealth(self: *ServiceRegistry, service_name: []const u8) !HealthStatus {
        const service = self.services.get(service_name) orelse return .unknown;
        
        // Implement health check logic
        // This would typically make HTTP requests to health endpoints
        
        return .healthy;
    }
};
```

---

## Troubleshooting

### Common Issues and Solutions

#### 1. Identity Generation Failures

**Problem**: `realid_generate_from_passphrase` fails with weak passphrase
```zig
const identity = shroud.sigil.realid_generate_from_passphrase("weak") catch |err| switch (err) {
    shroud.sigil.RealIDError.InvalidPassphrase => {
        std.debug.print("Passphrase too weak. Use at least 12 characters.\n");
        return;
    },
    else => return err,
};
```

**Solution**: Use strong passphrases (12+ characters, mixed case, numbers, symbols)

#### 2. Network Binding Issues

**Problem**: Server fails to bind to port
```zig
var server = shroud.ghostwire.createUnifiedServer(allocator, config) catch |err| switch (err) {
    shroud.ghostwire.TransportError.NetworkError => {
        std.debug.print("Network error. Check if port is already in use.\n");
        return;
    },
    else => return err,
};
```

**Solution**: Check port availability, run with appropriate permissions

#### 3. Signature Verification Failures

**Problem**: Valid signatures failing verification
```zig
// Debug signature verification
pub fn debugSignatureVerification(
    signature: shroud.sigil.RealIDSignature,
    message: []const u8,
    public_key: shroud.sigil.RealIDPublicKey
) void {
    std.debug.print("Message length: {d}\n", .{message.len});
    std.debug.print("Message hex: {}\n", .{std.fmt.fmtSliceHexLower(message)});
    std.debug.print("Signature: {}\n", .{std.fmt.fmtSliceHexLower(&signature.bytes)});
    std.debug.print("Public key: {}\n", .{std.fmt.fmtSliceHexLower(&public_key.bytes)});
    
    const is_valid = shroud.sigil.realid_verify(signature, message, public_key);
    std.debug.print("Verification result: {}\n", .{is_valid});
}
```

**Solution**: Ensure message data is exactly the same when signing and verifying

#### 4. Memory Management Issues

**Problem**: Memory leaks in long-running services
```zig
// Use arena allocators for request handling
pub fn handleRequest(allocator: std.mem.Allocator, request: Request) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit(); // Automatically frees all allocations
    
    const temp_allocator = arena.allocator();
    
    // All temporary allocations use temp_allocator
    const processed_data = try processRequestData(temp_allocator, request.data);
    // ... rest of processing
}
```

#### 5. Concurrent Access Issues

**Problem**: Race conditions in multi-threaded scenarios
```zig
const ThreadSafeService = struct {
    mutex: std.Thread.Mutex,
    data: ServiceData,
    
    pub fn updateData(self: *ThreadSafeService, new_data: ServiceData) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.data = new_data;
    }
    
    pub fn getData(self: *ThreadSafeService) ServiceData {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        return self.data;
    }
};
```

### Debugging Tools

#### 1. Network Traffic Analysis

```zig
pub fn enableNetworkLogging(server: *shroud.ghostwire.UnifiedServer) void {
    server.addMiddleware(loggingMiddleware);
}

fn loggingMiddleware(
    request: *shroud.ghostwire.UnifiedRequest,
    response: *shroud.ghostwire.UnifiedResponse,
    next: shroud.ghostwire.HandlerFn
) !void {
    const start_time = std.time.nanoTimestamp();
    
    std.debug.print("Request: {} {} from {s}\n", .{ request.method, request.path, request.remote_addr });
    
    try next(request, response);
    
    const duration = std.time.nanoTimestamp() - start_time;
    std.debug.print("Response: {} in {}ms\n", .{ response.status, duration / 1_000_000 });
}
```

#### 2. Cryptographic Operation Tracing

```zig
pub fn traceCryptoOperations() void {
    // Enable detailed logging for crypto operations
    // This would typically be a compile-time flag
}
```

---

## Performance Optimization

### 1. Memory Optimization

```zig
// Use fixed-size buffers for known data sizes
const SIGNATURE_SIZE = 64;
const PUBLIC_KEY_SIZE = 32;

pub const OptimizedHandler = struct {
    signature_buffer: [SIGNATURE_SIZE]u8,
    key_buffer: [PUBLIC_KEY_SIZE]u8,
    
    pub fn processSignature(self: *OptimizedHandler, signature_data: []const u8) !void {
        if (signature_data.len != SIGNATURE_SIZE) {
            return error.InvalidSignatureSize;
        }
        
        @memcpy(&self.signature_buffer, signature_data);
        // Process using stack-allocated buffer
    }
};
```

### 2. Batch Processing

```zig
pub const BatchProcessor = struct {
    batch_size: usize,
    pending_operations: std.ArrayList(Operation),
    
    pub fn addOperation(self: *BatchProcessor, operation: Operation) !void {
        try self.pending_operations.append(operation);
        
        if (self.pending_operations.items.len >= self.batch_size) {
            try self.processBatch();
        }
    }
    
    fn processBatch(self: *BatchProcessor) !void {
        // Process all pending operations together
        defer self.pending_operations.clearRetainingCapacity();
        
        for (self.pending_operations.items) |operation| {
            try self.processOperation(operation);
        }
    }
};
```

### 3. Connection Pooling

```zig
pub const ConnectionPool = struct {
    allocator: std.mem.Allocator,
    available_connections: std.ArrayList(*Connection),
    max_connections: usize,
    mutex: std.Thread.Mutex,
    
    pub fn getConnection(self: *ConnectionPool) !*Connection {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.available_connections.popOrNull()) |conn| {
            return conn;
        }
        
        if (self.available_connections.items.len < self.max_connections) {
            return try self.createConnection();
        }
        
        return error.NoAvailableConnections;
    }
    
    pub fn returnConnection(self: *ConnectionPool, conn: *Connection) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.available_connections.append(conn) catch {
            // Pool full, destroy connection
            conn.deinit();
        };
    }
};
```

---

*This implementation guide provides comprehensive examples for integrating Shroud into your crypto projects. For additional support, refer to the API documentation and framework documentation.*