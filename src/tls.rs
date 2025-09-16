use crate::config::{TlsConfig, TlsVersion};
use anyhow::Result;
use instant_acme::{Account, AuthorizationStatus, ChallengeType, Identifier, LetsEncrypt, NewAccount, NewOrder, OrderStatus};
use rcgen::{Certificate, CertificateParams, DistinguishedName, DnType, SanType};
use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer};
use rustls::{ServerConfig, SupportedCipherSuite};
use rustls_pemfile::{certs, pkcs8_private_keys};
use std::io::BufReader;
use std::path::Path;
use std::sync::Arc;
use std::time::SystemTime;
use tokio::fs;
use tracing::{info, warn};

pub fn create_server_config(config: &TlsConfig) -> Result<ServerConfig> {
    let mut tls_config = ServerConfig::builder();

    // Configure cipher suites based on TLS version
    let cipher_suites = get_cipher_suites(config);
    tls_config = tls_config
        .with_cipher_suites(&cipher_suites);

    // Load certificates and key
    let (cert_chain, private_key) = if config.auto_cert {
        // Try to load existing certificates or generate new ones
        load_or_generate_certificates(config)?
    } else {
        // Load from specified paths
        load_certificates_from_files(config)?
    };

    let server_config = tls_config
        .with_no_client_auth()
        .with_single_cert(cert_chain, private_key)?;

    info!("TLS configuration created successfully");
    Ok(server_config)
}

fn get_cipher_suites(config: &TlsConfig) -> Vec<SupportedCipherSuite> {
    match config.min_version {
        TlsVersion::Tls13 => {
            // TLS 1.3 cipher suites
            vec![
                rustls::cipher_suite::TLS13_AES_256_GCM_SHA384,
                rustls::cipher_suite::TLS13_CHACHA20_POLY1305_SHA256,
                rustls::cipher_suite::TLS13_AES_128_GCM_SHA256,
            ]
        }
        TlsVersion::Tls12 => {
            // TLS 1.2 cipher suites (for backward compatibility)
            vec![
                rustls::cipher_suite::TLS13_AES_256_GCM_SHA384,
                rustls::cipher_suite::TLS13_CHACHA20_POLY1305_SHA256,
                rustls::cipher_suite::TLS13_AES_128_GCM_SHA256,
                rustls::cipher_suite::TLS12_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
                rustls::cipher_suite::TLS12_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256,
                rustls::cipher_suite::TLS12_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
            ]
        }
    }
}

fn load_or_generate_certificates(config: &TlsConfig) -> Result<(Vec<CertificateDer<'static>>, PrivateKeyDer<'static>)> {
    let cert_path = config.cert_path.as_deref().unwrap_or("certs/server.crt");
    let key_path = config.key_path.as_deref().unwrap_or("certs/server.key");

    // Try to load existing certificates
    if Path::new(cert_path).exists() && Path::new(key_path).exists() {
        match load_certificates_from_files(config) {
            Ok(certs) => {
                info!("Loaded existing TLS certificates");
                return Ok(certs);
            }
            Err(e) => {
                warn!("Failed to load existing certificates: {}, generating new ones", e);
            }
        }
    }

    // Generate new self-signed certificates
    info!("Generating new self-signed certificates");
    let (cert, key) = generate_self_signed_cert_data("localhost")?;

    // Create certs directory if it doesn't exist
    if let Some(parent) = Path::new(cert_path).parent() {
        std::fs::create_dir_all(parent)?;
    }

    // Save to files
    std::fs::write(cert_path, &cert)?;
    std::fs::write(key_path, &key)?;

    info!("Saved certificates to {} and {}", cert_path, key_path);

    // Parse the generated certificates
    let cert_chain = certs(&mut BufReader::new(cert.as_slice()))
        .collect::<Result<Vec<_>, _>>()?;

    let mut keys = pkcs8_private_keys(&mut BufReader::new(key.as_slice()))
        .collect::<Result<Vec<_>, _>>()?;

    if keys.is_empty() {
        return Err(anyhow::anyhow!("No private keys found"));
    }

    let private_key = PrivateKeyDer::Pkcs8(keys.remove(0));

    Ok((cert_chain, private_key))
}

fn load_certificates_from_files(config: &TlsConfig) -> Result<(Vec<CertificateDer<'static>>, PrivateKeyDer<'static>)> {
    let cert_path = config.cert_path.as_ref()
        .ok_or_else(|| anyhow::anyhow!("Certificate path not specified"))?;
    let key_path = config.key_path.as_ref()
        .ok_or_else(|| anyhow::anyhow!("Private key path not specified"))?;

    // Load certificate chain
    let cert_file = std::fs::File::open(cert_path)?;
    let mut cert_reader = BufReader::new(cert_file);
    let cert_chain = certs(&mut cert_reader)
        .collect::<Result<Vec<_>, _>>()?;

    if cert_chain.is_empty() {
        return Err(anyhow::anyhow!("No certificates found in {}", cert_path));
    }

    // Load private key
    let key_file = std::fs::File::open(key_path)?;
    let mut key_reader = BufReader::new(key_file);
    let mut keys = pkcs8_private_keys(&mut key_reader)
        .collect::<Result<Vec<_>, _>>()?;

    if keys.is_empty() {
        return Err(anyhow::anyhow!("No private keys found in {}", key_path));
    }

    let private_key = PrivateKeyDer::Pkcs8(keys.remove(0));

    Ok((cert_chain, private_key))
}

pub fn generate_self_signed_cert(domain: &str) -> Result<()> {
    let (cert_pem, key_pem) = generate_self_signed_cert_data(domain)?;

    // Create certs directory
    std::fs::create_dir_all("certs")?;

    // Write certificate and key files
    std::fs::write("certs/server.crt", cert_pem)?;
    std::fs::write("certs/server.key", key_pem)?;

    info!("Self-signed certificate generated for domain: {}", domain);
    Ok(())
}

fn generate_self_signed_cert_data(domain: &str) -> Result<(Vec<u8>, Vec<u8>)> {
    let mut params = CertificateParams::new(vec![domain.to_string()]);

    // Set certificate parameters
    params.distinguished_name = DistinguishedName::new();
    params.distinguished_name.push(DnType::CommonName, domain);
    params.distinguished_name.push(DnType::OrganizationName, "Wraith");
    params.distinguished_name.push(DnType::OrganizationalUnitName, "IT Department");

    // Add Subject Alternative Names
    params.subject_alt_names = vec![
        SanType::DnsName(domain.to_string()),
        SanType::DnsName("localhost".to_string()),
        SanType::IpAddress(std::net::IpAddr::V4(std::net::Ipv4Addr::new(127, 0, 0, 1))),
        SanType::IpAddress(std::net::IpAddr::V6(std::net::Ipv6Addr::new(0, 0, 0, 0, 0, 0, 0, 1))),
    ];

    // Set validity period (1 year)
    let now = SystemTime::now();
    params.not_before = now.into();
    params.not_after = (now + std::time::Duration::from_secs(365 * 24 * 60 * 60)).into();

    // Generate certificate
    let cert = Certificate::from_params(params)?;

    let cert_pem = cert.serialize_pem()?;
    let key_pem = cert.serialize_private_key_pem();

    Ok((cert_pem.into_bytes(), key_pem.into_bytes()))
}

pub async fn generate_acme_cert_dns(domain: &str) -> Result<()> {
    info!("Generating ACME certificate for domain: {}", domain);

    // Create Let's Encrypt account
    let (account, _) = Account::create(
        &NewAccount {
            contact: &[],
            terms_of_service_agreed: true,
            only_return_existing: false,
        },
        LetsEncrypt::Production.url(),
        None,
    ).await?;

    // Create new order
    let identifier = Identifier::Dns(domain.to_string());
    let (mut order, order_url) = account
        .new_order(&NewOrder {
            identifiers: &[identifier],
        })
        .await?;

    info!("Created ACME order for domain: {}", domain);

    // Get authorizations
    let authorizations = order.authorizations().await?;

    for authz in &authorizations {
        match authz.status {
            AuthorizationStatus::Pending => {
                // Find DNS challenge
                let challenge = authz
                    .challenges
                    .iter()
                    .find(|c| c.r#type == ChallengeType::Dns01)
                    .ok_or_else(|| anyhow::anyhow!("No DNS-01 challenge found"))?;

                let key_auth = order.key_authorization(challenge);
                let dns_value = instant_acme::dns_value(&key_auth);

                info!(
                    "Please create DNS TXT record:\n\
                     Name: _acme-challenge.{}\n\
                     Value: {}\n\
                     Press Enter when ready...",
                    domain, dns_value
                );

                // Wait for user confirmation
                let mut input = String::new();
                std::io::stdin().read_line(&mut input)?;

                // Ready the challenge
                order.set_challenge_ready(&challenge.url).await?;
            }
            AuthorizationStatus::Valid => {
                info!("Authorization already valid for {}", authz.identifier);
            }
            _ => {
                return Err(anyhow::anyhow!(
                    "Unexpected authorization status: {:?}",
                    authz.status
                ));
            }
        }
    }

    // Wait for order to be ready
    let mut tries = 1u8;
    let mut delay = std::time::Duration::from_millis(250);
    loop {
        tokio::time::sleep(delay).await;
        order.refresh().await?;

        match order.status() {
            OrderStatus::Ready => {
                info!("Order ready, finalizing...");
                break;
            }
            OrderStatus::Invalid => {
                return Err(anyhow::anyhow!("Order is invalid"));
            }
            OrderStatus::Processing => {
                info!("Order processing...");
            }
            _ => {
                if tries < 5 {
                    tries += 1;
                    delay *= 2;
                    continue;
                } else {
                    return Err(anyhow::anyhow!("Order not ready after {} tries", tries));
                }
            }
        }
    }

    // Generate private key and CSR
    let mut params = CertificateParams::new(vec![domain.to_string()]);
    params.distinguished_name = DistinguishedName::new();
    params.distinguished_name.push(DnType::CommonName, domain);

    let cert = Certificate::from_params(params)?;
    let csr = cert.serialize_request_der()?;

    // Finalize order
    order.finalize(&csr).await?;

    // Wait for certificate
    loop {
        tokio::time::sleep(std::time::Duration::from_secs(1)).await;
        order.refresh().await?;

        match order.status() {
            OrderStatus::Valid => {
                info!("Certificate issued!");
                break;
            }
            OrderStatus::Invalid => {
                return Err(anyhow::anyhow!("Order is invalid"));
            }
            _ => {
                info!("Waiting for certificate...");
            }
        }
    }

    // Download certificate
    let cert_chain_pem = order.certificate().await?.ok_or_else(|| {
        anyhow::anyhow!("Certificate not available")
    })?;

    // Create certs directory
    fs::create_dir_all("certs").await?;

    // Save certificate and key
    fs::write("certs/server.crt", cert_chain_pem).await?;
    fs::write("certs/server.key", cert.serialize_private_key_pem()).await?;

    info!("ACME certificate saved to certs/server.crt and certs/server.key");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_self_signed_cert() {
        let result = generate_self_signed_cert_data("test.example.com");
        assert!(result.is_ok());

        let (cert_pem, key_pem) = result.unwrap();
        assert!(!cert_pem.is_empty());
        assert!(!key_pem.is_empty());

        // Verify PEM format
        assert!(std::str::from_utf8(&cert_pem).unwrap().contains("BEGIN CERTIFICATE"));
        assert!(std::str::from_utf8(&key_pem).unwrap().contains("BEGIN PRIVATE KEY"));
    }
}