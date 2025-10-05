# Development Guide

This guide covers building, testing, and contributing to Wraith.

## Prerequisites

### Required Tools

- **Zig 0.16.0-dev** or later ([Download](https://ziglang.org/download/))
- **Git** for version control
- **curl** or **wget** for fetching dependencies

### Optional Tools

- **Docker** for containerized testing
- **Python 3** for test utilities
- **jq** for JSON log parsing
- **sqlite3** for inspecting log database

### Platform Support

- ✅ Linux (x86_64, aarch64)
- ✅ macOS (x86_64, aarch64/Apple Silicon)
- ⚠️ Windows (experimental, WSL2 recommended)
- ✅ FreeBSD (x86_64)

## Building from Source

### Clone Repository

```bash
git clone https://github.com/yourusername/wraith.git
cd wraith
```

### Build Commands

```bash
# Debug build (fast compile, slow runtime)
zig build

# Release build (optimized)
zig build -Doptimize=ReleaseFast

# Small binary (optimized for size)
zig build -Doptimize=ReleaseSmall

# Safe release (with runtime safety checks)
zig build -Doptimize=ReleaseSafe

# Run directly
zig build run -- serve -c wraith.toml

# Install to prefix
zig build install --prefix ~/.local
```

### Build Artifacts

```
zig-out/
├── bin/
│   └── wraith              # Main executable
└── lib/                    # Shared libraries (if any)
```

### Cross-Compilation

```bash
# Linux x86_64
zig build -Dtarget=x86_64-linux -Doptimize=ReleaseFast

# Linux ARM64
zig build -Dtarget=aarch64-linux -Doptimize=ReleaseFast

# macOS x86_64
zig build -Dtarget=x86_64-macos -Doptimize=ReleaseFast

# macOS Apple Silicon
zig build -Dtarget=aarch64-macos -Doptimize=ReleaseFast

# Windows
zig build -Dtarget=x86_64-windows -Doptimize=ReleaseFast
```

## Project Structure

```
wraith/
├── build.zig              # Build configuration
├── build.zig.zon          # Package manifest
├── src/
│   ├── main.zig           # Entry point
│   ├── root.zig           # Library root
│   ├── cli/
│   │   └── commands.zig   # CLI parsing
│   ├── config/
│   │   └── config.zig     # Configuration
│   ├── server/
│   │   ├── http_server.zig
│   │   ├── signals.zig
│   │   └── tls.zig
│   ├── proxy/
│   │   └── forwarder.zig
│   ├── routing/
│   │   └── router.zig
│   └── upstream/
│       └── manager.zig
├── tests/
│   ├── integration/
│   ├── unit/
│   └── bench/
├── docs/
├── examples/
└── scripts/
```

## Testing

### Unit Tests

```bash
# Run all tests
zig build test

# Run specific test file
zig build test -- src/config/config.zig

# Verbose output
zig build test --summary all

# Generate coverage report
zig build test -Dcoverage=true
```

### Integration Tests

```bash
# Run integration tests
./scripts/integration-test.sh

# Run specific test suite
./scripts/integration-test.sh proxy
./scripts/integration-test.sh tls
./scripts/integration-test.sh quic
```

### Example Integration Test

```zig
// tests/integration/proxy_test.zig
const std = @import("std");
const testing = std.testing;
const Wraith = @import("wraith");

test "basic proxy forwarding" {
    const allocator = testing.allocator;

    // Start mock upstream
    var upstream = try MockUpstream.init(allocator, 8080);
    defer upstream.deinit();

    // Configure wraith
    var config = Wraith.config.Config{
        .server = .{
            .listen = &[_][]const u8{"127.0.0.1:9000"},
        },
        .upstreams = &[_]Wraith.config.UpstreamConfig{
            .{
                .name = "test",
                .servers = &[_][]const u8{"http://127.0.0.1:8080"},
            },
        },
        .routes = &[_]Wraith.config.RouteConfig{
            .{
                .path = "/",
                .upstream = "test",
            },
        },
    };

    // Start wraith
    var server = try Wraith.server.HttpServer.init(allocator, config);
    defer server.deinit();

    try server.start();

    // Make request
    const response = try std.http.Client.get("http://127.0.0.1:9000/test");
    try testing.expectEqual(@as(u16, 200), response.status);
}
```

### Benchmarks

```bash
# Run benchmarks
zig build bench

# Specific benchmark
zig build bench -- forwarding

# With profiling
zig build bench -Dprofile=true
```

### Load Testing

```bash
# Using Apache Bench
ab -n 100000 -c 100 http://localhost:9000/

# Using wrk
wrk -t12 -c400 -d30s http://localhost:9000/

# Using hey
hey -n 100000 -c 100 http://localhost:9000/

# Using vegeta
echo "GET http://localhost:9000/" | vegeta attack -duration=30s -rate=1000 | vegeta report
```

## Development Workflow

### Running in Development Mode

```bash
# Start with auto-reload on file changes
./scripts/dev-watch.sh

# Or manually with debug logging
zig build run -- serve -c wraith.toml --log-level=debug
```

### Hot Reload Testing

```bash
# Terminal 1: Start server
zig build run -- serve -c wraith.toml

# Terminal 2: Make config changes, then reload
vim wraith.toml
kill -HUP $(pgrep wraith)

# Or use the CLI
wraith reload
```

### Debugging

```bash
# Build with debug symbols
zig build -Doptimize=Debug

# Run with GDB
gdb zig-out/bin/wraith
(gdb) run serve -c wraith.toml
(gdb) bt  # backtrace on crash

# Run with LLDB
lldb zig-out/bin/wraith
(lldb) run serve -c wraith.toml
(lldb) bt  # backtrace on crash

# Memory leak detection (Valgrind)
valgrind --leak-check=full zig-out/bin/wraith serve -c wraith.toml

# Address Sanitizer
zig build -Doptimize=Debug -Dsanitize-thread=true
zig build -Doptimize=Debug -Dsanitize-address=true
```

### Code Coverage

```bash
# Generate coverage report
zig build test -Dcoverage=true

# View HTML report
./scripts/coverage-report.sh
open coverage/index.html
```

## Code Style

### Formatting

```bash
# Format all Zig files
zig fmt .

# Check formatting without modifying
zig fmt --check .

# Format specific file
zig fmt src/main.zig
```

### Linting

```bash
# Run linter (Zig has built-in checks)
zig build --summary all

# Static analysis
zig build analyze
```

### Naming Conventions

- **Types**: `PascalCase` - `HttpServer`, `Config`, `RouteConfig`
- **Functions**: `camelCase` - `parseConfig`, `forwardRequest`
- **Constants**: `SCREAMING_SNAKE_CASE` - `MAX_CONNECTIONS`, `DEFAULT_PORT`
- **Variables**: `snake_case` - `server_addr`, `request_count`

### Example Code

```zig
const std = @import("std");

/// HTTP server configuration
pub const ServerConfig = struct {
    /// Listen addresses
    listen: []const []const u8,

    /// Worker thread count (0 = auto)
    worker_threads: u32 = 0,

    /// Initialize server config with defaults
    pub fn init(allocator: std.mem.Allocator) !ServerConfig {
        return ServerConfig{
            .listen = try allocator.dupe([]const u8, &[_][]const u8{"0.0.0.0:9000"}),
            .worker_threads = 0,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *ServerConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.listen);
    }
};

test "ServerConfig initialization" {
    const allocator = std.testing.allocator;

    var config = try ServerConfig.init(allocator);
    defer config.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), config.listen.len);
    try std.testing.expectEqualStrings("0.0.0.0:9000", config.listen[0]);
}
```

## Dependency Management

### Adding Dependencies

```bash
# Add new dependency to build.zig.zon
zig fetch --save https://github.com/user/package/archive/refs/heads/main.tar.gz

# Update specific dependency
zig fetch --save=package_name https://github.com/user/package/archive/v1.2.3.tar.gz
```

### Updating Dependencies

```bash
# Update all dependencies
./scripts/update-deps.sh

# Check for outdated dependencies
./scripts/check-deps.sh
```

### build.zig.zon Example

```zig
.{
    .name = "wraith",
    .version = "0.1.0",
    .paths = .{""},

    .dependencies = .{
        .zsync = .{
            .url = "https://github.com/ghostkellz/zsync/archive/main.tar.gz",
            .hash = "1220...",
        },
        .zhttp = .{
            .url = "https://github.com/ghostkellz/zhttp/archive/main.tar.gz",
            .hash = "1220...",
        },
    },
}
```

## Contributing

### Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/yourusername/wraith.git
   cd wraith
   git remote add upstream https://github.com/originaluser/wraith.git
   ```

3. **Create a feature branch**:
   ```bash
   git checkout -b feature/my-new-feature
   ```

4. **Make your changes** and commit:
   ```bash
   git add .
   git commit -m "feat: add awesome new feature"
   ```

5. **Push to your fork**:
   ```bash
   git push origin feature/my-new-feature
   ```

6. **Open a Pull Request** on GitHub

### Commit Message Format

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types:**
- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation changes
- `style` - Code style changes (formatting)
- `refactor` - Code refactoring
- `perf` - Performance improvements
- `test` - Adding/updating tests
- `chore` - Build/tooling changes

**Examples:**
```
feat(proxy): add weighted load balancing

Implements weighted round-robin algorithm for distributing
requests based on server capacity.

Closes #123

---

fix(tls): resolve certificate loading on Alpine Linux

The certificate loading was failing on Alpine due to missing
ca-certificates package in the Docker image.

---

docs(config): add QUIC configuration examples

Added examples for QUIC settings including post-quantum
cryptography options.
```

### Pull Request Guidelines

- **Keep PRs focused** - One feature/fix per PR
- **Write tests** - Add unit/integration tests for new code
- **Update docs** - Update README/docs if needed
- **Run tests locally** - Ensure `zig build test` passes
- **Format code** - Run `zig fmt .` before committing
- **Link issues** - Reference related issues in PR description

### Code Review Process

1. **Automated checks** run on PR (CI/CD)
2. **Maintainer review** - 1-2 maintainers review code
3. **Address feedback** - Make requested changes
4. **Approval** - Maintainer approves PR
5. **Merge** - PR is merged to main branch

### Running CI Checks Locally

```bash
# Run all CI checks
./scripts/ci-check.sh

# Individual checks
zig fmt --check .           # Format check
zig build test              # Unit tests
./scripts/integration-test.sh  # Integration tests
zig build --summary all     # Build check
```

## Release Process

### Version Numbering

Wraith follows [Semantic Versioning](https://semver.org/):
- `MAJOR.MINOR.PATCH` (e.g., `1.2.3`)
- `MAJOR` - Breaking changes
- `MINOR` - New features (backwards compatible)
- `PATCH` - Bug fixes (backwards compatible)

### Creating a Release

```bash
# Update version in build.zig.zon
vim build.zig.zon

# Update CHANGELOG.md
vim CHANGELOG.md

# Commit version bump
git commit -am "chore: bump version to v1.2.3"
git tag v1.2.3
git push origin main --tags

# CI will automatically build and publish release
```

### Release Checklist

- [ ] Update version in `build.zig.zon`
- [ ] Update `CHANGELOG.md` with release notes
- [ ] Run full test suite: `zig build test`
- [ ] Run integration tests: `./scripts/integration-test.sh`
- [ ] Build release binaries: `./scripts/build-release.sh`
- [ ] Test release binaries on target platforms
- [ ] Create git tag: `git tag v1.2.3`
- [ ] Push tag: `git push --tags`
- [ ] Create GitHub release with binaries
- [ ] Update package manager repositories (AUR, Homebrew, etc.)
- [ ] Announce release (blog, social media, Discord)

## Troubleshooting Development Issues

### Build Failures

```bash
# Clear cache and rebuild
rm -rf zig-cache zig-out
zig build

# Update Zig compiler
# Download latest from https://ziglang.org/download/
```

### Dependency Issues

```bash
# Re-fetch dependencies
rm -rf ~/.cache/zig/p
zig build

# Verify dependency hashes
zig build --fetch
```

### Test Failures

```bash
# Run single test with verbose output
zig test src/config/config.zig --summary all

# Run with leak detection
zig test src/config/config.zig -ftrack-allocations
```

### Performance Issues

```bash
# Profile with perf (Linux)
perf record -g zig-out/bin/wraith serve -c wraith.toml
perf report

# Profile with Instruments (macOS)
instruments -t "Time Profiler" zig-out/bin/wraith serve -c wraith.toml

# Flamegraph
./scripts/flamegraph.sh
```

## Resources

### Documentation
- [Zig Language Reference](https://ziglang.org/documentation/master/)
- [Zig Standard Library](https://ziglang.org/documentation/master/std/)
- [Wraith Architecture](./architecture.md)
- [Configuration Reference](./configuration.md)

### Community
- **GitHub Discussions** - https://github.com/yourusername/wraith/discussions
- **Discord** - https://discord.gg/wraith
- **IRC** - #wraith on Libera.Chat

### Related Projects
- [zsync](https://github.com/ghostkellz/zsync) - Async runtime
- [zhttp](https://github.com/ghostkellz/zhttp) - HTTP library
- [zcrypto](https://github.com/ghostkellz/zcrypto) - Cryptography
- [zquic](https://github.com/ghostkellz/zquic) - QUIC implementation
