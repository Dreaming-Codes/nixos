use anyhow::{bail, Context, Result};
use lan_mouse_proto::{ProtoEvent, MAX_EVENT_SIZE};
use sha2::{Digest, Sha256};
use std::io::{BufReader, BufWriter, Read, Write};
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;
use tokio::net::UdpSocket;
use tokio::sync::mpsc;
use webrtc_dtls::config::{Config, ExtendedMasterSecretType};
use webrtc_dtls::conn::DTLSConn;
use webrtc_dtls::crypto::Certificate;
use webrtc_util::Conn;

fn cert_path() -> PathBuf {
    let config_dir = std::env::var("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            let home = std::env::var("HOME").expect("HOME not set");
            PathBuf::from(home).join(".config")
        });
    config_dir.join("lan-mouse-grab").join("cert.pem")
}

fn load_or_generate_cert() -> Result<Certificate> {
    let path = cert_path();
    if path.exists() {
        let f = std::fs::File::open(&path)?;
        let mut reader = BufReader::new(f);
        let mut pem = String::new();
        reader.read_to_string(&mut pem)?;
        Ok(Certificate::from_pem(&pem)?)
    } else {
        let cert = Certificate::generate_self_signed(["ignored".to_owned()])?;
        let pem = cert.serialize_pem();
        let parent = path.parent().expect("cert path has parent");
        std::fs::create_dir_all(parent)?;
        let f = std::fs::File::create(&path)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perm = f.metadata()?.permissions();
            perm.set_mode(0o400);
            f.set_permissions(perm)?;
        }
        let mut writer = BufWriter::new(f);
        writer.write_all(pem.as_bytes())?;
        Ok(cert)
    }
}

fn certificate_fingerprint(cert: &Certificate) -> String {
    let der = cert.certificate.first().expect("certificate missing");
    let mut hasher = Sha256::new();
    hasher.update(der);
    hasher
        .finalize()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect::<Vec<_>>()
        .join(":")
}

pub struct DtlsConnection {
    conn: Arc<dyn Conn + Send + Sync>,
    fingerprint: String,
}

impl DtlsConnection {
    pub async fn connect(addr: SocketAddr) -> Result<Self> {
        let cert = load_or_generate_cert().context("failed to load/generate certificate")?;
        let fingerprint = certificate_fingerprint(&cert);

        let udp = Arc::new(UdpSocket::bind("0.0.0.0:0").await?);
        udp.connect(addr).await?;

        let config = Config {
            certificates: vec![cert],
            server_name: "ignored".to_owned(),
            insecure_skip_verify: true,
            extended_master_secret: ExtendedMasterSecretType::Require,
            ..Default::default()
        };

        let conn = tokio::time::timeout(
            Duration::from_secs(10),
            DTLSConn::new(udp, config, true, None),
        )
        .await
        .context("DTLS connection timed out")?
        .map_err(|e| anyhow::anyhow!("DTLS handshake failed: {e}"))?;

        Ok(Self {
            conn: Arc::new(conn),
            fingerprint,
        })
    }

    pub fn fingerprint(&self) -> &str {
        &self.fingerprint
    }

    pub async fn send(&self, event: ProtoEvent) -> Result<()> {
        let (buf, len): ([u8; MAX_EVENT_SIZE], usize) = event.into();
        self.conn.send(&buf[..len]).await?;
        Ok(())
    }

    pub async fn recv(&self) -> Result<ProtoEvent> {
        let mut buf = [0u8; MAX_EVENT_SIZE];
        self.conn.recv(&mut buf).await?;
        Ok(buf
            .try_into()
            .map_err(|e| anyhow::anyhow!("protocol error: {e}"))?)
    }

    pub async fn ping_until_alive(&self) -> Result<()> {
        for _ in 0..8 {
            self.send(ProtoEvent::Ping).await?;
            tokio::time::sleep(Duration::from_millis(250)).await;
        }

        loop {
            let event = tokio::time::timeout(Duration::from_secs(5), self.recv())
                .await
                .context("no Pong received from remote")??;
            match event {
                ProtoEvent::Pong(true) => return Ok(()),
                ProtoEvent::Pong(false) => bail!("remote emulation is disabled"),
                _ => continue,
            }
        }
    }

    pub async fn wait_for_ack(&self) -> Result<()> {
        let ack = tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                match self.recv().await? {
                    ProtoEvent::Ack(_) => return Ok::<_, anyhow::Error>(()),
                    _ => continue,
                }
            }
        })
        .await
        .context("no Ack received from remote")??;
        Ok(ack)
    }
}

pub fn get_fingerprint() -> Result<String> {
    let cert = load_or_generate_cert()?;
    Ok(certificate_fingerprint(&cert))
}

pub enum ConnectionState {
    Disconnected,
    Connected(DtlsConnection),
}

pub struct ConnectionManager {
    state: ConnectionState,
    addr: Option<SocketAddr>,
    event_tx: mpsc::UnboundedSender<ConnectionEvent>,
}

pub enum ConnectionEvent {
    Connected,
    Disconnected(String),
    SendError(String),
}

impl ConnectionManager {
    pub fn new(event_tx: mpsc::UnboundedSender<ConnectionEvent>) -> Self {
        Self {
            state: ConnectionState::Disconnected,
            addr: None,
            event_tx,
        }
    }

    pub async fn resolve_and_connect(&mut self, host: &str, port: u16) -> Result<()> {
        let addr_str = format!("{host}:{port}");
        let addr = tokio::net::lookup_host(&addr_str)
            .await
            .context("DNS lookup failed")?
            .next()
            .context("no addresses resolved")?;
        self.addr = Some(addr);
        self.try_connect().await
    }

    pub async fn try_connect(&mut self) -> Result<()> {
        let addr = self.addr.context("no address set")?;
        log::info!("connecting to {addr}...");

        let conn = DtlsConnection::connect(addr).await?;
        log::info!("DTLS connected, fingerprint: {}", conn.fingerprint());

        conn.ping_until_alive().await?;
        log::info!("remote is alive, sending Enter...");

        conn.send(ProtoEvent::Enter(lan_mouse_proto::Position::Right))
            .await?;
        conn.wait_for_ack().await?;
        log::info!("capture session established");

        self.state = ConnectionState::Connected(conn);
        let _ = self.event_tx.send(ConnectionEvent::Connected);
        Ok(())
    }

    pub async fn send(&self, event: ProtoEvent) -> bool {
        if let ConnectionState::Connected(conn) = &self.state {
            if let Err(e) = conn.send(event).await {
                log::warn!("send error: {e}");
                return false;
            }
            true
        } else {
            false
        }
    }

    pub async fn disconnect(&mut self) {
        if let ConnectionState::Connected(conn) = &self.state {
            let _ = conn.send(ProtoEvent::Leave(0)).await;
        }
        self.state = ConnectionState::Disconnected;
    }

    pub fn is_connected(&self) -> bool {
        matches!(self.state, ConnectionState::Connected(_))
    }
}
