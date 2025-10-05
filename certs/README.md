# Development Certificates

This directory contains TLS certificates for development use.

## Generate Development Certificates

For development, you can generate self-signed certificates:

```bash
# Generate a self-signed certificate for localhost
openssl req -x509 -newkey rsa:4096 -keyout server.key -out server.crt -days 365 -nodes -subj "/CN=localhost"

# Or use Wraith's built-in certificate generation
./zig-out/bin/wraith generate certs --dev --hostname localhost
```

## Production Certificates

For production, use ACME/Let's Encrypt integration:

```bash
# Enable auto-cert in wraith.toml
./zig-out/bin/wraith generate certs --dns --domain example.com
```

## Certificate Files

- `server.crt` - TLS certificate chain
- `server.key` - Private key (keep secure!)
- `ca.crt` - Certificate Authority (if using custom CA)

⚠️ **Never commit private keys to version control!**
