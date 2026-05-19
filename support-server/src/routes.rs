use axum::{
    extract::{Path, State},
    http::{header, StatusCode},
    response::{Html, IntoResponse, Response},
    Json,
};
use lettre::{
    message::header::ContentType, transport::smtp::authentication::Credentials, AsyncSmtpTransport,
    AsyncTransport, Message, Tokio1Executor,
};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::sync::Arc;

use crate::{
    sessions::{Session, SessionStatus},
    AppState, EmailConfig,
};

// ── Request / Response types ──────────────────────────────────────────────────

#[derive(Serialize)]
pub struct CreateSessionRes {
    pub session_id: String,
}

#[derive(Deserialize)]
pub struct UpdateSessionReq {
    pub rustdesk_id: Option<String>,
    pub status: Option<SessionStatus>,
}

#[derive(Deserialize)]
pub struct ClaimReq {
    pub rustdesk_id: String,
}

#[derive(Deserialize)]
pub struct SupportRequestReq {
    /// The user's RustDesk ID (required for the agent to connect)
    pub rustdesk_id: String,
    /// Optional display name shown in the dashboard and email
    pub name: Option<String>,
    /// Optional description of the issue
    pub message: Option<String>,
}

// ── Helpers ───────────────────────────────────────────────────────────────────

fn broadcast(state: &AppState, event_type: &str, session: &Session) {
    let msg = json!({ "type": event_type, "session": session }).to_string();
    let _ = state.tx.send(msg);
}

async fn send_ready_email(cfg: Arc<EmailConfig>, rdid: String, server_url: String) {
    let dashboard_url = format!("{}/dashboard", server_url);
    let subject = format!("Support request ready — ID: {}", rdid);
    let body = format!(
        r#"<!DOCTYPE html>
<html><body style="font-family:system-ui,sans-serif;max-width:480px;margin:40px auto;color:#1e293b">
  <h2 style="margin:0 0 16px">New support request</h2>
  <p style="margin:0 0 8px;color:#64748b">A user needs help. Their Helpdesk ID:</p>
  <p style="font-size:2.2em;font-weight:700;font-family:monospace;color:#2563eb;letter-spacing:3px;margin:16px 0;background:#eff6ff;padding:14px 20px;border-radius:8px;display:inline-block">{}</p>
  <p style="margin:16px 0 8px;color:#374151;font-size:14px">
    Open the dashboard and click <strong>Connect</strong> next to this session.
  </p>
  <a href="{}"
     style="display:inline-block;padding:12px 24px;background:#2563eb;color:#fff;text-decoration:none;border-radius:8px;font-weight:600;font-size:15px">
    Open Dashboard
  </a>
</body></html>"#,
        rdid, dashboard_url
    );

    let email = match Message::builder()
        .from(cfg.gmail_user.parse().unwrap())
        .to(cfg.notify_email.parse().unwrap())
        .subject(subject)
        .header(ContentType::TEXT_HTML)
        .body(body)
    {
        Ok(e) => e,
        Err(e) => {
            tracing::warn!("Failed to build email: {}", e);
            return;
        }
    };

    let creds = Credentials::new(cfg.gmail_user.clone(), cfg.gmail_password.clone());
    let mailer = match AsyncSmtpTransport::<Tokio1Executor>::relay("smtp.gmail.com") {
        Ok(m) => m.credentials(creds).build(),
        Err(e) => {
            tracing::warn!("Failed to create SMTP transport: {}", e);
            return;
        }
    };

    match mailer.send(email).await {
        Ok(_) => tracing::info!("Email sent → {}", cfg.notify_email),
        Err(e) => tracing::warn!("Failed to send email: {}", e),
    }
}

async fn send_waiting_email(cfg: Arc<EmailConfig>, server_url: String) {
    let dashboard_url = format!("{}/dashboard", server_url);
    let subject = "Support request — user is online".to_string();
    let body = format!(
        r#"<!DOCTYPE html>
<html><body style="font-family:system-ui,sans-serif;max-width:480px;margin:40px auto;color:#1e293b">
  <h2 style="margin:0 0 16px">User ready for support</h2>
  <p style="margin:0 0 16px;color:#374151;font-size:14px">
    A returning user has opened Helpdesk and is waiting for you to connect.
    Their ID is visible in the Helpdesk window on their screen.
  </p>
  <a href="{}"
     style="display:inline-block;padding:12px 24px;background:#2563eb;color:#fff;text-decoration:none;border-radius:8px;font-weight:600;font-size:15px">
    Open Dashboard
  </a>
</body></html>"#,
        dashboard_url
    );

    let email = match Message::builder()
        .from(cfg.gmail_user.parse().unwrap())
        .to(cfg.notify_email.parse().unwrap())
        .subject(subject)
        .header(ContentType::TEXT_HTML)
        .body(body)
    {
        Ok(e) => e,
        Err(e) => {
            tracing::warn!("Failed to build waiting email: {}", e);
            return;
        }
    };

    let creds = Credentials::new(cfg.gmail_user.clone(), cfg.gmail_password.clone());
    let mailer = match AsyncSmtpTransport::<Tokio1Executor>::relay("smtp.gmail.com") {
        Ok(m) => m.credentials(creds).build(),
        Err(e) => {
            tracing::warn!("Failed to create SMTP transport: {}", e);
            return;
        }
    };

    match mailer.send(email).await {
        Ok(_) => tracing::info!("Waiting email sent → {}", cfg.notify_email),
        Err(e) => tracing::warn!("Failed to send waiting email: {}", e),
    }
}

/// Sends a rich notification email when a user submits the in-app request form.
/// Includes their name, issue description, and RustDesk ID.
async fn send_support_request_email(
    cfg: Arc<EmailConfig>,
    rdid: String,
    name: String,
    msg: String,
    server_url: String,
) {
    let dashboard_url = format!("{}/dashboard", server_url);
    let subject = format!("Support request from {} — ID: {}", name, rdid);
    // Escape minimal HTML so the message renders safely
    let safe_name = msg_escape(&name);
    let safe_msg = msg_escape(&msg);
    let body = format!(
        r#"<!DOCTYPE html>
<html><body style="font-family:system-ui,sans-serif;max-width:500px;margin:40px auto;color:#1e293b">
  <h2 style="margin:0 0 20px">New support request</h2>
  <table style="width:100%;border-collapse:collapse;margin-bottom:24px;font-size:14px">
    <tr>
      <td style="padding:8px 12px 8px 0;color:#64748b;white-space:nowrap;vertical-align:top">From</td>
      <td style="padding:8px 0;font-weight:600">{}</td>
    </tr>
    <tr>
      <td style="padding:8px 12px 8px 0;color:#64748b;vertical-align:top">Issue</td>
      <td style="padding:8px 0;line-height:1.6;white-space:pre-wrap">{}</td>
    </tr>
  </table>
  <p style="margin:0 0 8px;color:#64748b;font-size:13px">Their Support ID:</p>
  <p style="font-size:2em;font-weight:700;font-family:monospace;color:#2563eb;letter-spacing:3px;margin:0 0 24px;background:#eff6ff;padding:14px 20px;border-radius:8px;display:inline-block">{}</p>
  <p style="margin:0 0 16px;color:#374151;font-size:14px">
    Open the dashboard and click <strong>Connect</strong> next to this session.
  </p>
  <a href="{}"
     style="display:inline-block;padding:12px 24px;background:#2563eb;color:#fff;text-decoration:none;border-radius:8px;font-weight:600;font-size:15px">
    Open Dashboard
  </a>
</body></html>"#,
        safe_name, safe_msg, rdid, dashboard_url
    );

    let email = match Message::builder()
        .from(cfg.gmail_user.parse().unwrap())
        .to(cfg.notify_email.parse().unwrap())
        .subject(subject)
        .header(ContentType::TEXT_HTML)
        .body(body)
    {
        Ok(e) => e,
        Err(e) => {
            tracing::warn!("Failed to build support-request email: {}", e);
            return;
        }
    };

    let creds = Credentials::new(cfg.gmail_user.clone(), cfg.gmail_password.clone());
    let mailer = match AsyncSmtpTransport::<Tokio1Executor>::relay("smtp.gmail.com") {
        Ok(m) => m.credentials(creds).build(),
        Err(e) => {
            tracing::warn!("Failed to create SMTP transport: {}", e);
            return;
        }
    };

    match mailer.send(email).await {
        Ok(_) => tracing::info!("Support-request email sent → {}", cfg.notify_email),
        Err(e) => tracing::warn!("Failed to send support-request email: {}", e),
    }
}

/// Minimal HTML escaper — keeps the email body safe when user input is embedded.
fn msg_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

// ── Handlers ──────────────────────────────────────────────────────────────────

/// POST /api/session — widget opens a session when user clicks Get Support
pub async fn create_session(State(state): State<AppState>) -> (StatusCode, Json<CreateSessionRes>) {
    let session = Session::new();
    let id = session.id.clone();
    broadcast(&state, "new_session", &session);
    state.sessions.write().await.insert(id.clone(), session);
    (
        StatusCode::CREATED,
        Json(CreateSessionRes { session_id: id }),
    )
}

/// POST /api/session/:id/notify — widget calls this when Helpdesk is already installed
/// and the app opened (blur detected). Marks session as ready and sends a waiting email.
pub async fn notify_session(State(state): State<AppState>, Path(id): Path<String>) -> StatusCode {
    let mut sessions = state.sessions.write().await;
    let Some(session) = sessions.get_mut(&id) else {
        return StatusCode::NOT_FOUND;
    };
    session.status = SessionStatus::Ready;
    let updated = session.clone();
    drop(sessions);

    broadcast(&state, "session_updated", &updated);

    if let Some(cfg) = state.email.clone() {
        let server_url = state.server_url.clone();
        tokio::spawn(async move { send_waiting_email(cfg, server_url).await });
    }

    StatusCode::OK
}

/// GET /api/sessions — dashboard fetches all sessions
pub async fn list_sessions(State(state): State<AppState>) -> Json<Vec<Session>> {
    let sessions = state.sessions.read().await;
    let mut list: Vec<Session> = sessions.values().cloned().collect();
    list.sort_by(|a, b| b.created_at.cmp(&a.created_at));
    Json(list)
}

/// GET /api/session/:id — widget polls for session status
pub async fn get_session(State(state): State<AppState>, Path(id): Path<String>) -> Response {
    let sessions = state.sessions.read().await;
    match sessions.get(&id) {
        Some(s) => Json(s.clone()).into_response(),
        None => StatusCode::NOT_FOUND.into_response(),
    }
}

/// POST /api/session/claim — installer phones home after getting the RustDesk ID.
/// Matches to the oldest pending session (FIFO).
pub async fn claim_session(
    State(state): State<AppState>,
    Json(body): Json<ClaimReq>,
) -> StatusCode {
    let mut sessions = state.sessions.write().await;

    let maybe_id = sessions
        .values()
        .filter(|s| s.status == SessionStatus::Pending)
        .min_by_key(|s| s.created_at)
        .map(|s| s.id.clone());

    let Some(id) = maybe_id else {
        return StatusCode::NOT_FOUND;
    };

    let session = sessions.get_mut(&id).unwrap();
    session.rustdesk_id = Some(body.rustdesk_id.clone());
    session.status = SessionStatus::Ready;
    let updated = session.clone();
    drop(sessions);

    broadcast(&state, "session_updated", &updated);

    if let Some(cfg) = state.email.clone() {
        let rdid = body.rustdesk_id.clone();
        let server_url = state.server_url.clone();
        tokio::spawn(async move { send_ready_email(cfg, rdid, server_url).await });
    }

    StatusCode::OK
}

/// PATCH /api/session/:id — agent updates session (status change)
pub async fn update_session(
    State(state): State<AppState>,
    Path(id): Path<String>,
    Json(body): Json<UpdateSessionReq>,
) -> Response {
    let mut sessions = state.sessions.write().await;
    let Some(session) = sessions.get_mut(&id) else {
        return StatusCode::NOT_FOUND.into_response();
    };

    if let Some(rid) = body.rustdesk_id {
        session.rustdesk_id = Some(rid);
        session.status = SessionStatus::Ready;
    }
    if let Some(status) = body.status {
        session.status = status;
    }

    let updated = session.clone();
    drop(sessions);

    broadcast(&state, "session_updated", &updated);
    Json(updated).into_response()
}

/// DELETE /api/session/:id — agent closes a session
pub async fn close_session(State(state): State<AppState>, Path(id): Path<String>) -> StatusCode {
    let mut sessions = state.sessions.write().await;
    let Some(session) = sessions.get_mut(&id) else {
        return StatusCode::NOT_FOUND;
    };
    session.status = SessionStatus::Closed;
    let updated = session.clone();
    drop(sessions);
    broadcast(&state, "session_updated", &updated);
    StatusCode::OK
}

/// GET /widget.js
pub async fn serve_widget(State(_state): State<AppState>) -> Response {
    let js = include_str!("../static/widget.js");
    ([(header::CONTENT_TYPE, "application/javascript")], js).into_response()
}

/// GET /dashboard
pub async fn serve_dashboard() -> Html<&'static str> {
    Html(include_str!("../static/dashboard.html"))
}

/// GET /request — user-facing "Request Support" form page
pub async fn serve_request() -> Html<&'static str> {
    Html(include_str!("../static/request.html"))
}

/// POST /api/support-request — in-app "Request Support" form.
/// User supplies their RustDesk ID plus optional name and issue description.
/// Creates a Ready session immediately and fires a detailed notification email.
pub async fn handle_support_request(
    State(state): State<AppState>,
    Json(body): Json<SupportRequestReq>,
) -> (StatusCode, Json<CreateSessionRes>) {
    let mut session = Session::new();
    session.rustdesk_id = Some(body.rustdesk_id.clone());
    session.status = SessionStatus::Ready;
    session.name = body.name.clone();
    session.message = body.message.clone();

    let id = session.id.clone();
    broadcast(&state, "new_session", &session);
    state.sessions.write().await.insert(id.clone(), session);

    if let Some(cfg) = state.email.clone() {
        let rdid = body.rustdesk_id.clone();
        let name = body.name.clone().unwrap_or_else(|| "Anonymous".to_string());
        let msg = body
            .message
            .clone()
            .unwrap_or_else(|| "(no description provided)".to_string());
        let server_url = state.server_url.clone();
        tokio::spawn(
            async move { send_support_request_email(cfg, rdid, name, msg, server_url).await },
        );
    }

    (
        StatusCode::CREATED,
        Json(CreateSessionRes { session_id: id }),
    )
}

/// GET /test
pub async fn serve_test() -> Html<&'static str> {
    Html(
        r##"<!DOCTYPE html>
<html>
<head><title>Test Page</title></head>
<body style="font-family:system-ui;padding:40px;max-width:600px;margin:auto">
  <p>This is a test page. Click the button at the bottom-right to request support.</p>
  <p style="margin-top:24px;font-size:13px;color:#64748b">
    Widget options: <code>data-color</code>, <code>data-label</code>,
    <code>data-position</code> (left/right), <code>data-bottom</code>, <code>data-side</code> (px).
  </p>
  <script src="/widget.js"
    data-color="#2563eb"
    data-label="Remote Support"
    data-position="right"
    data-bottom="24"
    data-side="24">
  </script>
</body>
</html>"##,
    )
}

/// GET /download/windows — agent PS1 script
pub async fn download_windows() -> Response {
    let script = include_str!("../client-deploy/install.ps1");
    (
        [
            (header::CONTENT_TYPE, "application/octet-stream"),
            (
                header::CONTENT_DISPOSITION,
                "attachment; filename=\"rustdesk-install.ps1\"",
            ),
        ],
        script,
    )
        .into_response()
}

/// GET /download/windows-installer — pre-configured end-user .exe
pub async fn download_windows_installer() -> Response {
    match std::fs::read("static/SupportClient-Setup.exe") {
        Ok(bytes) => (
            [
                (header::CONTENT_TYPE, "application/octet-stream"),
                (
                    header::CONTENT_DISPOSITION,
                    "attachment; filename=\"SupportClient-Setup.exe\"",
                ),
            ],
            bytes,
        )
            .into_response(),
        Err(_) => (
            StatusCode::NOT_FOUND,
            "Installer not built yet. Run installer/build.sh first.",
        )
            .into_response(),
    }
}

/// GET /download/linux — agent shell script
pub async fn download_linux() -> Response {
    let script = include_str!("../client-deploy/install.sh");
    (
        [
            (header::CONTENT_TYPE, "application/octet-stream"),
            (
                header::CONTENT_DISPOSITION,
                "attachment; filename=\"rustdesk-install.sh\"",
            ),
        ],
        script,
    )
        .into_response()
}
