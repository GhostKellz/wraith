use crate::config::DnsConfig;
use anyhow::Result;
use hickory_resolver::{TokioAsyncResolver, config::*};
use hickory_server::{
    authority::MessageResponseBuilder,
    proto::{
        op::{Header, Message, MessageType, OpCode, ResponseCode},
        rr::{DNSClass, Name, RData, Record, RecordType},
    },
    server::{Request, RequestHandler, ResponseHandler, ResponseInfo},
    ServerFuture,
};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::net::{TcpListener, UdpSocket};
use tracing::{info, warn, error};

pub struct DnsServer {
    config: DnsConfig,
    resolver: TokioAsyncResolver,
}

impl DnsServer {
    pub async fn new(config: DnsConfig) -> Result<Self> {
        let resolver = TokioAsyncResolver::tokio(
            ResolverConfig::default(),
            ResolverOpts::default(),
        )?;

        Ok(Self { config, resolver })
    }

    pub async fn start(&self) -> Result<()> {
        if !self.config.doh_enabled && !self.config.dot_enabled {
            info!("DNS server disabled");
            return Ok(());
        }

        let handler = DnsHandler {
            resolver: self.resolver.clone(),
            config: self.config.clone(),
        };

        let mut server = ServerFuture::new(handler);

        if self.config.dot_enabled {
            // DNS over TLS (DoT)
            let addr: SocketAddr = "0.0.0.0:853".parse()?;
            let listener = TcpListener::bind(addr).await?;
            info!("DNS over TLS (DoT) server listening on {}", addr);

            // TODO: Add TLS configuration for DoT
            // server.register_tls_listener(listener, Duration::from_secs(5), pkcs12)?;
        }

        if self.config.doh_enabled {
            // DNS over HTTPS will be handled by the main HTTP server
            info!("DNS over HTTPS (DoH) enabled at path: {}", self.config.doh_path);
        }

        // Start UDP DNS server for testing
        let udp_socket = UdpSocket::bind("0.0.0.0:5353").await?;
        info!("DNS server listening on UDP 5353");
        server.register_socket(udp_socket);

        server.block_until_done().await?;

        Ok(())
    }

    pub async fn handle_doh_query(&self, query: &[u8]) -> Result<Vec<u8>> {
        // Parse DNS query and resolve it
        let message = Message::from_vec(query)?;

        // For now, just return a simple response
        let mut header = Header::new();
        header.set_id(message.id());
        header.set_message_type(MessageType::Response);
        header.set_op_code(OpCode::Query);
        header.set_response_code(ResponseCode::NoError);

        let response = Message::new();
        Ok(response.to_vec()?)
    }
}

#[derive(Clone)]
struct DnsHandler {
    resolver: TokioAsyncResolver,
    config: DnsConfig,
}

#[async_trait::async_trait]
impl RequestHandler for DnsHandler {
    async fn handle_request<R: ResponseHandler>(
        &self,
        request: &Request,
        mut response_handle: R,
    ) -> ResponseInfo {
        let builder = MessageResponseBuilder::from_message_request(request);
        let mut header = Header::response_from_request(request.header());

        match request.op_code() {
            OpCode::Query => {
                match self.handle_query(request).await {
                    Ok(records) => {
                        header.set_response_code(ResponseCode::NoError);
                        let response = builder.build(header, records.iter(), &[], &[], &[]);
                        match response_handle.send_response(response).await {
                            Ok(info) => info,
                            Err(e) => {
                                error!("Failed to send DNS response: {}", e);
                                ResponseInfo::from(header)
                            }
                        }
                    }
                    Err(e) => {
                        warn!("DNS query failed: {}", e);
                        header.set_response_code(ResponseCode::ServFail);
                        let response = builder.build_no_records(header);
                        match response_handle.send_response(response).await {
                            Ok(info) => info,
                            Err(e) => {
                                error!("Failed to send DNS error response: {}", e);
                                ResponseInfo::from(header)
                            }
                        }
                    }
                }
            }
            _ => {
                header.set_response_code(ResponseCode::NotImp);
                let response = builder.build_no_records(header);
                match response_handle.send_response(response).await {
                    Ok(info) => info,
                    Err(e) => {
                        error!("Failed to send DNS not implemented response: {}", e);
                        ResponseInfo::from(header)
                    }
                }
            }
        }
    }
}

impl DnsHandler {
    async fn handle_query(&self, request: &Request) -> Result<Vec<Record>> {
        let mut records = Vec::new();

        for query in request.queries() {
            match query.query_type() {
                RecordType::A => {
                    if let Ok(response) = self.resolver.lookup_ip(query.name().to_utf8()).await {
                        for ip in response.iter() {
                            if let std::net::IpAddr::V4(ipv4) = ip {
                                let record = Record::from_rdata(
                                    query.name().clone(),
                                    300, // TTL
                                    RData::A(ipv4.into()),
                                );
                                records.push(record);
                            }
                        }
                    }
                }
                RecordType::AAAA => {
                    if let Ok(response) = self.resolver.lookup_ip(query.name().to_utf8()).await {
                        for ip in response.iter() {
                            if let std::net::IpAddr::V6(ipv6) = ip {
                                let record = Record::from_rdata(
                                    query.name().clone(),
                                    300, // TTL
                                    RData::AAAA(ipv6.into()),
                                );
                                records.push(record);
                            }
                        }
                    }
                }
                _ => {
                    // For other record types, we'll just return empty for now
                    warn!("Unsupported DNS record type: {:?}", query.query_type());
                }
            }
        }

        Ok(records)
    }
}