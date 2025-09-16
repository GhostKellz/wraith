use anyhow::Result;
use prometheus::{Counter, Gauge, Histogram, Registry, TextEncoder, Encoder};
use std::collections::HashMap;
use once_cell::sync::Lazy;

static REGISTRY: Lazy<Registry> = Lazy::new(|| Registry::new());

static HTTP_REQUESTS_TOTAL: Lazy<Counter> = Lazy::new(|| {
    let counter = Counter::new("http_requests_total", "Total HTTP requests").unwrap();
    REGISTRY.register(Box::new(counter.clone())).unwrap();
    counter
});

static HTTP_REQUEST_DURATION: Lazy<Histogram> = Lazy::new(|| {
    let histogram = Histogram::new("http_request_duration_seconds", "HTTP request duration").unwrap();
    REGISTRY.register(Box::new(histogram.clone())).unwrap();
    histogram
});

static ACTIVE_CONNECTIONS: Lazy<Gauge> = Lazy::new(|| {
    let gauge = Gauge::new("active_connections", "Number of active connections").unwrap();
    REGISTRY.register(Box::new(gauge.clone())).unwrap();
    gauge
});

pub struct MetricsCollector {
    registry: &'static Registry,
}

impl MetricsCollector {
    pub fn new() -> Self {
        Self {
            registry: &REGISTRY,
        }
    }

    pub fn record_request(&self) {
        HTTP_REQUESTS_TOTAL.inc();
    }

    pub fn record_request_duration(&self, duration: f64) {
        HTTP_REQUEST_DURATION.observe(duration);
    }

    pub fn set_active_connections(&self, count: f64) {
        ACTIVE_CONNECTIONS.set(count);
    }

    pub fn export_metrics(&self) -> Result<String> {
        let encoder = TextEncoder::new();
        let metric_families = self.registry.gather();
        let mut buffer = Vec::new();
        encoder.encode(&metric_families, &mut buffer)?;
        Ok(String::from_utf8(buffer)?)
    }
}

impl Default for MetricsCollector {
    fn default() -> Self {
        Self::new()
    }
}