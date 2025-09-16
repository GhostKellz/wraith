use crate::config::StaticConfig;
use anyhow::Result;
use bytes::Bytes;
use flate2::{write::GzEncoder, Compression};
use http::{HeaderMap, HeaderValue, Response, StatusCode};
use ring::digest::{Context, SHA256};
use std::collections::HashMap;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::SystemTime;
use tokio::sync::RwLock;
use tracing::{debug, warn};

#[derive(Clone)]
pub struct StaticFileServer {
    config: StaticConfig,
    file_cache: Arc<RwLock<HashMap<String, CachedFile>>>,
    mime_types: HashMap<String, &'static str>,
}

#[derive(Clone)]
struct CachedFile {
    content: Bytes,
    compressed_content: Option<Bytes>,
    etag: String,
    mime_type: String,
    last_modified: SystemTime,
    file_size: u64,
}

impl StaticFileServer {
    pub fn new(config: StaticConfig) -> Self {
        let mime_types = create_mime_type_map();

        Self {
            config,
            file_cache: Arc::new(RwLock::new(HashMap::new())),
            mime_types,
        }
    }

    pub async fn serve_file(
        &self,
        path: &str,
        headers: &HeaderMap,
    ) -> Result<(Response<()>, Option<Bytes>)> {
        if !self.config.enabled {
            return Ok((
                Response::builder()
                    .status(StatusCode::NOT_FOUND)
                    .body(())?,
                Some(Bytes::from("Static file serving disabled")),
            ));
        }

        // Sanitize path to prevent directory traversal
        let safe_path = self.sanitize_path(path)?;
        let full_path = PathBuf::from(&self.config.root).join(&safe_path);

        debug!("Serving static file: {:?}", full_path);

        // Check if file exists
        let metadata = match fs::metadata(&full_path) {
            Ok(metadata) => metadata,
            Err(_) => {
                // Try index files if path is a directory
                if full_path.is_dir() {
                    return self.try_serve_index(&full_path, headers).await;
                }
                return self.not_found_response();
            }
        };

        // Don't serve directories directly unless autoindex is enabled
        if metadata.is_dir() {
            if self.config.autoindex {
                return self.serve_directory_listing(&full_path).await;
            } else {
                return self.try_serve_index(&full_path, headers).await;
            }
        }

        // Get file from cache or read from disk
        let cached_file = self.get_cached_file(&full_path, &metadata).await?;

        // Check if-none-match (ETag)
        if let Some(if_none_match) = headers.get("if-none-match") {
            if let Ok(etag_str) = if_none_match.to_str() {
                if etag_str.contains(&cached_file.etag) {
                    return Ok((
                        Response::builder()
                            .status(StatusCode::NOT_MODIFIED)
                            .header("etag", &cached_file.etag)
                            .body(())?,
                        None,
                    ));
                }
            }
        }

        // Check if-modified-since
        if let Some(if_modified_since) = headers.get("if-modified-since") {
            if let Ok(ims_str) = if_modified_since.to_str() {
                if let Ok(ims_time) = httpdate::parse_http_date(ims_str) {
                    if cached_file.last_modified <= ims_time {
                        return Ok((
                            Response::builder()
                                .status(StatusCode::NOT_MODIFIED)
                                .header("etag", &cached_file.etag)
                                .body(())?,
                            None,
                        ));
                    }
                }
            }
        }

        // Check if client accepts gzip compression
        let accept_gzip = headers
            .get("accept-encoding")
            .and_then(|v| v.to_str().ok())
            .map(|s| s.contains("gzip"))
            .unwrap_or(false);

        let (content, content_encoding) = if accept_gzip
            && self.config.compression
            && cached_file.compressed_content.is_some()
            && self.should_compress(&cached_file.mime_type)
        {
            (
                cached_file.compressed_content.as_ref().unwrap().clone(),
                Some("gzip"),
            )
        } else {
            (cached_file.content.clone(), None)
        };

        // Build response
        let mut response_builder = Response::builder()
            .status(StatusCode::OK)
            .header("content-type", &cached_file.mime_type)
            .header("content-length", content.len())
            .header("last-modified", httpdate::fmt_http_date(cached_file.last_modified));

        if self.config.etag {
            response_builder = response_builder.header("etag", &cached_file.etag);
        }

        if let Some(cache_control) = &self.config.cache_control {
            response_builder = response_builder.header("cache-control", cache_control);
        }

        if let Some(encoding) = content_encoding {
            response_builder = response_builder.header("content-encoding", encoding);
        }

        // Add security headers
        response_builder = response_builder
            .header("x-content-type-options", "nosniff")
            .header("x-frame-options", "DENY");

        Ok((response_builder.body(())?, Some(content)))
    }

    async fn get_cached_file(
        &self,
        path: &Path,
        metadata: &fs::Metadata,
    ) -> Result<CachedFile> {
        let path_str = path.to_string_lossy().to_string();
        let last_modified = metadata.modified()?;

        // Check cache
        {
            let cache = self.file_cache.read().await;
            if let Some(cached) = cache.get(&path_str) {
                if cached.last_modified >= last_modified {
                    return Ok(cached.clone());
                }
            }
        }

        // Read file from disk
        let content = fs::read(path)?;
        let content_bytes = Bytes::from(content);

        // Generate ETag
        let etag = if self.config.etag {
            generate_etag(&content_bytes, last_modified)
        } else {
            String::new()
        };

        // Determine MIME type
        let mime_type = self.get_mime_type(path);

        // Compress if needed
        let compressed_content = if self.config.compression && self.should_compress(&mime_type) {
            Some(compress_gzip(&content_bytes)?)
        } else {
            None
        };

        let cached_file = CachedFile {
            content: content_bytes,
            compressed_content,
            etag,
            mime_type,
            last_modified,
            file_size: metadata.len(),
        };

        // Update cache
        {
            let mut cache = self.file_cache.write().await;
            cache.insert(path_str, cached_file.clone());
        }

        Ok(cached_file)
    }

    async fn try_serve_index(
        &self,
        dir_path: &Path,
        headers: &HeaderMap,
    ) -> Result<(Response<()>, Option<Bytes>)> {
        for index_file in &self.config.index_files {
            let index_path = dir_path.join(index_file);
            if index_path.exists() && index_path.is_file() {
                let metadata = fs::metadata(&index_path)?;
                let cached_file = self.get_cached_file(&index_path, &metadata).await?;

                // Build simple response for index file
                return Ok((
                    Response::builder()
                        .status(StatusCode::OK)
                        .header("content-type", &cached_file.mime_type)
                        .header("content-length", cached_file.content.len())
                        .body(())?,
                    Some(cached_file.content),
                ));
            }
        }

        self.not_found_response()
    }

    async fn serve_directory_listing(
        &self,
        dir_path: &Path,
    ) -> Result<(Response<()>, Option<Bytes>)> {
        let entries = fs::read_dir(dir_path)?;
        let mut html = String::from(
            r#"<!DOCTYPE html>
<html>
<head>
    <title>Directory Listing</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        a { text-decoration: none; color: #0066cc; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <h1>Directory Listing</h1>
    <table>
        <tr><th>Name</th><th>Size</th><th>Modified</th></tr>"#,
        );

        for entry in entries {
            let entry = entry?;
            let metadata = entry.metadata()?;
            let name = entry.file_name().to_string_lossy();
            let size = if metadata.is_dir() {
                "-".to_string()
            } else {
                format_size(metadata.len())
            };
            let modified = httpdate::fmt_http_date(metadata.modified()?);

            html.push_str(&format!(
                r#"<tr><td><a href="{}">{}</a></td><td>{}</td><td>{}</td></tr>"#,
                name, name, size, modified
            ));
        }

        html.push_str("</table></body></html>");

        Ok((
            Response::builder()
                .status(StatusCode::OK)
                .header("content-type", "text/html; charset=utf-8")
                .header("content-length", html.len())
                .body(())?,
            Some(Bytes::from(html)),
        ))
    }

    fn sanitize_path(&self, path: &str) -> Result<String> {
        // Remove leading slash and resolve relative paths
        let path = path.trim_start_matches('/');
        let path = Path::new(path);

        // Check for directory traversal attempts
        for component in path.components() {
            if let std::path::Component::ParentDir = component {
                return Err(anyhow::anyhow!("Directory traversal attempted"));
            }
        }

        Ok(path.to_string_lossy().to_string())
    }

    fn get_mime_type(&self, path: &Path) -> String {
        let extension = path
            .extension()
            .and_then(|ext| ext.to_str())
            .map(|ext| ext.to_lowercase())
            .unwrap_or_default();

        self.mime_types
            .get(&extension)
            .unwrap_or(&"application/octet-stream")
            .to_string()
    }

    fn should_compress(&self, mime_type: &str) -> bool {
        self.config.compression_types.iter().any(|ct| mime_type.starts_with(ct))
    }

    fn not_found_response(&self) -> Result<(Response<()>, Option<Bytes>)> {
        Ok((
            Response::builder()
                .status(StatusCode::NOT_FOUND)
                .header("content-type", "text/html")
                .body(())?,
            Some(Bytes::from(
                r#"<!DOCTYPE html>
<html>
<head><title>404 Not Found</title></head>
<body>
<h1>404 Not Found</h1>
<p>The requested resource was not found on this server.</p>
<hr>
<p><em>Wraith HTTP/3 Server</em></p>
</body>
</html>"#,
            )),
        ))
    }

    pub async fn get_cache_stats(&self) -> HashMap<String, serde_json::Value> {
        let cache = self.file_cache.read().await;
        let mut stats = HashMap::new();

        stats.insert("cached_files".to_string(), cache.len().into());

        let total_size: u64 = cache.values().map(|f| f.file_size).sum();
        stats.insert("total_cached_size".to_string(), total_size.into());

        let compressed_files = cache.values().filter(|f| f.compressed_content.is_some()).count();
        stats.insert("compressed_files".to_string(), compressed_files.into());

        stats
    }
}

fn generate_etag(content: &Bytes, last_modified: SystemTime) -> String {
    let mut context = Context::new(&SHA256);
    context.update(content);

    // Include last modified time in hash for uniqueness
    if let Ok(duration) = last_modified.duration_since(SystemTime::UNIX_EPOCH) {
        context.update(&duration.as_secs().to_be_bytes());
    }

    let digest = context.finish();
    format!(r#""{}""#, hex::encode(&digest.as_ref()[..8]))
}

fn compress_gzip(content: &Bytes) -> Result<Bytes> {
    let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
    encoder.write_all(content)?;
    let compressed = encoder.finish()?;
    Ok(Bytes::from(compressed))
}

fn format_size(size: u64) -> String {
    const UNITS: &[&str] = &["B", "KB", "MB", "GB", "TB"];
    let mut size = size as f64;
    let mut unit_index = 0;

    while size >= 1024.0 && unit_index < UNITS.len() - 1 {
        size /= 1024.0;
        unit_index += 1;
    }

    format!("{:.1} {}", size, UNITS[unit_index])
}

fn create_mime_type_map() -> HashMap<String, &'static str> {
    let mut map = HashMap::new();

    // Text
    map.insert("html".to_string(), "text/html; charset=utf-8");
    map.insert("htm".to_string(), "text/html; charset=utf-8");
    map.insert("txt".to_string(), "text/plain; charset=utf-8");
    map.insert("css".to_string(), "text/css; charset=utf-8");
    map.insert("js".to_string(), "application/javascript; charset=utf-8");
    map.insert("json".to_string(), "application/json; charset=utf-8");
    map.insert("xml".to_string(), "application/xml; charset=utf-8");

    // Images
    map.insert("png".to_string(), "image/png");
    map.insert("jpg".to_string(), "image/jpeg");
    map.insert("jpeg".to_string(), "image/jpeg");
    map.insert("gif".to_string(), "image/gif");
    map.insert("svg".to_string(), "image/svg+xml");
    map.insert("ico".to_string(), "image/x-icon");
    map.insert("webp".to_string(), "image/webp");

    // Fonts
    map.insert("woff".to_string(), "font/woff");
    map.insert("woff2".to_string(), "font/woff2");
    map.insert("ttf".to_string(), "font/ttf");
    map.insert("otf".to_string(), "font/otf");
    map.insert("eot".to_string(), "application/vnd.ms-fontobject");

    // Documents
    map.insert("pdf".to_string(), "application/pdf");
    map.insert("zip".to_string(), "application/zip");
    map.insert("tar".to_string(), "application/x-tar");
    map.insert("gz".to_string(), "application/gzip");

    // Media
    map.insert("mp4".to_string(), "video/mp4");
    map.insert("webm".to_string(), "video/webm");
    map.insert("mp3".to_string(), "audio/mpeg");
    map.insert("wav".to_string(), "audio/wav");
    map.insert("ogg".to_string(), "audio/ogg");

    map
}