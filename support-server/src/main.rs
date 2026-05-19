mod routes;
mod sessions;
mod ws;

use axum::{
    routing::{delete, get, patch, post},
    Router,
};
use sessions::SessionMap;
use std::{collections::HashMap, sync::Arc};
use tokio::sync::{broadcast, RwLock};
use tower_http::{cors::CorsLayer, trace::TraceLayer};
use tracing_subscriber::EnvFilter;

#[derive(Clone)]
pub struct EmailConfig {
    pub gmail_user: String,
    pub gmail_password: String,
    pub notify_email: String,
}

#[derive(Clone)]
pub struct AppState {
    pub sessions: SessionMap,
    pub tx: broadcast::Sender<String>,
    pub email: Option<Arc<EmailConfig>>,
    pub server_url: String,
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "rustdesk_support=debug,tower_http=debug".into()),
        )
        .init();

    let sessions: SessionMap = Arc::new(RwLock::new(HashMap::new()));
    let (tx, _) = broadcast::channel::<String>(256);

    // Email config — all three vars must be set to enable notifications
    let email = match (
        std::env::var("GMAIL_USER"),
        std::env::var("GMAIL_APP_PASSWORD"),
        std::env::var("NOTIFY_EMAIL"),
    ) {
        (Ok(user), Ok(password), Ok(notify)) => {
            tracing::info!("Gmail notifications enabled → {}", notify);
            Some(Arc::new(EmailConfig {
                gmail_user: user,
                gmail_password: password,
                notify_email: notify,
            }))
        }
        _ => {
            tracing::warn!("Gmail notifications disabled (set GMAIL_USER, GMAIL_APP_PASSWORD, NOTIFY_EMAIL to enable)");
            None
        }
    };

    let port = std::env::var("PORT").unwrap_or("3030".into());
    let server_url =
        std::env::var("SERVER_URL").unwrap_or_else(|_| format!("http://localhost:{port}"));

    let state = AppState {
        sessions,
        tx,
        email,
        server_url,
    };

    let app = Router::new()
        // Widget + dashboard
        .route("/widget.js", get(routes::serve_widget))
        .route("/dashboard", get(routes::serve_dashboard))
        .route("/request", get(routes::serve_request))
        .route("/test", get(routes::serve_test))
        // Downloads
        .route("/download/windows", get(routes::download_windows))
        .route(
            "/download/windows-installer",
            get(routes::download_windows_installer),
        )
        .route("/download/linux", get(routes::download_linux))
        // Session API
        .route("/api/session", post(routes::create_session))
        .route("/api/sessions", get(routes::list_sessions))
        .route("/api/session/claim", post(routes::claim_session))
        .route("/api/session/:id/notify", post(routes::notify_session))
        .route("/api/session/:id", get(routes::get_session))
        .route("/api/session/:id", patch(routes::update_session))
        .route("/api/session/:id", delete(routes::close_session))
        // In-app support request
        .route("/api/support-request", post(routes::handle_support_request))
        // Agent WebSocket
        .route("/ws/agent", get(ws::agent_ws_handler))
        .layer(TraceLayer::new_for_http())
        .layer(CorsLayer::permissive())
        .with_state(state);
    let addr = format!("0.0.0.0:{port}");

    tracing::info!("Support server running on http://{}", addr);
    tracing::info!("Agent dashboard → http://{}/dashboard", addr);
    tracing::info!(
        "Embed widget    → <script src=\"http://{}/widget.js\"></script>",
        addr
    );

    let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
