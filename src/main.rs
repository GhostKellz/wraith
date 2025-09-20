use anyhow::Result;
use clap::{Parser, Subcommand};
use std::path::PathBuf;
use tracing::{error, info};

mod config;
mod proxy;
mod server;

use config::Config;
use server::WraithServer;

#[derive(Parser)]
#[command(
    name = "wraith",
    version,
    about = "Modern HTTP reverse proxy and static server",
    long_about = None
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Start the Wraith server
    Serve {
        /// Configuration file path
        #[arg(short, long, default_value = "wraith.toml")]
        config: PathBuf,

        /// Development mode with self-signed certificates
        #[arg(long)]
        dev: bool,
    },

    /// Test configuration file syntax (like nginx -t)
    Test {
        /// Configuration file path
        #[arg(short, long, default_value = "wraith.toml")]
        config: PathBuf,
    },

    /// Reload configuration (like nginx -s reload)
    Reload {
        /// Configuration file path
        #[arg(short, long, default_value = "wraith.toml")]
        config: PathBuf,

        /// Admin API endpoint
        #[arg(long, default_value = "http://127.0.0.1:9090")]
        endpoint: String,
    },

    /// Stop the running server (like nginx -s stop)
    Stop {
        /// Admin API endpoint
        #[arg(long, default_value = "http://127.0.0.1:9090")]
        endpoint: String,
    },

    /// Gracefully stop the server (like nginx -s quit)
    Quit {
        /// Admin API endpoint
        #[arg(long, default_value = "http://127.0.0.1:9090")]
        endpoint: String,
    },

    /// Check server status
    Status {
        /// Admin API endpoint
        #[arg(long, default_value = "http://127.0.0.1:9090")]
        endpoint: String,
    },

    /// Show version information
    Version,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "wraith=info".into()),
        )
        .with_target(false)
        .with_thread_ids(false)
        .with_thread_names(false)
        .init();

    let cli = Cli::parse();

    match cli.command {
        Commands::Serve { config, dev } => {
            info!("🔥 Wraith - Modern HTTP Reverse Proxy starting...");

            let config = if dev {
                info!("🔧 Running in development mode");
                Config::development()
            } else {
                Config::from_file(&config).await?
            };

            let server = WraithServer::new(config).await?;

            info!("🚀 Wraith server started successfully!");

            if let Err(e) = server.run().await {
                error!("Server error: {}", e);
                std::process::exit(1);
            }
        }

        Commands::Test { config } => {
            info!("🔍 Testing configuration file: {}", config.display());

            match Config::from_file(&config).await {
                Ok(_) => {
                    info!("✅ Configuration test successful");
                    println!("wraith: the configuration file {} syntax is ok", config.display());
                    println!("wraith: configuration file {} test is successful", config.display());
                }
                Err(e) => {
                    error!("❌ Configuration test failed: {}", e);
                    println!("wraith: [emerg] configuration file {} test failed", config.display());
                    std::process::exit(1);
                }
            }
        }

        Commands::Reload { config, endpoint } => {
            info!("♻️ Reloading configuration...");

            let new_config = match Config::from_file(&config).await {
                Ok(config) => config,
                Err(e) => {
                    error!("❌ Failed to load configuration: {}", e);
                    std::process::exit(1);
                }
            };

            let client = reqwest::Client::new();
            let response = client
                .post(format!("{}/admin/reload", endpoint))
                .json(&new_config)
                .send()
                .await;

            match response {
                Ok(resp) if resp.status().is_success() => {
                    info!("✅ Configuration reloaded successfully");
                    println!("wraith: signal process started");
                }
                Ok(resp) => {
                    error!("❌ Failed to reload configuration: {}", resp.status());
                    std::process::exit(1);
                }
                Err(e) => {
                    error!("❌ Failed to connect to admin API: {}", e);
                    println!("wraith: could not open error log file: open() failed");
                    std::process::exit(1);
                }
            }
        }

        Commands::Stop { endpoint } => {
            info!("🛑 Stopping server...");

            let client = reqwest::Client::new();
            let response = client
                .post(format!("{}/admin/stop", endpoint))
                .send()
                .await;

            match response {
                Ok(resp) if resp.status().is_success() => {
                    info!("✅ Server stop signal sent");
                    println!("wraith: signal process started");
                }
                Ok(_) | Err(_) => {
                    error!("❌ Failed to connect to admin API");
                    println!("wraith: could not open error log file: open() failed");
                    std::process::exit(1);
                }
            }
        }

        Commands::Quit { endpoint } => {
            info!("🚪 Gracefully stopping server...");

            let client = reqwest::Client::new();
            let response = client
                .post(format!("{}/admin/quit", endpoint))
                .send()
                .await;

            match response {
                Ok(resp) if resp.status().is_success() => {
                    info!("✅ Server quit signal sent");
                    println!("wraith: signal process started");
                }
                Ok(_) | Err(_) => {
                    error!("❌ Failed to connect to admin API");
                    println!("wraith: could not open error log file: open() failed");
                    std::process::exit(1);
                }
            }
        }

        Commands::Status { endpoint } => {
            info!("📊 Fetching server status...");

            let client = reqwest::Client::new();
            let response = client.get(format!("{}/admin/health", endpoint)).send().await;

            match response {
                Ok(resp) if resp.status().is_success() => {
                    let status: serde_json::Value = resp.json().await?;
                    println!("Server Status: {}", serde_json::to_string_pretty(&status)?);
                }
                Ok(resp) => {
                    error!("❌ Failed to fetch status: {}", resp.status());
                    std::process::exit(1);
                }
                Err(e) => {
                    error!("❌ Failed to connect to admin API: {}", e);
                    std::process::exit(1);
                }
            }
        }

        Commands::Version => {
            println!("Wraith v{}", env!("CARGO_PKG_VERSION"));
            println!("Modern reverse proxy and static server");
            println!("Built with Rust");
        }
    }

    Ok(())
}