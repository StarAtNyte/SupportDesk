use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum SessionStatus {
    Pending, // user clicked widget, hasn't given RustDesk ID yet
    Ready,   // user provided their RustDesk ID, waiting for agent
    Active,  // agent connected
    Closed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub id: String,
    pub rustdesk_id: Option<String>,
    pub status: SessionStatus,
    pub created_at: DateTime<Utc>,
    /// User's display name — supplied via the in-app request form (optional)
    pub name: Option<String>,
    /// Short description of the issue — supplied via the in-app request form (optional)
    pub message: Option<String>,
}

impl Session {
    pub fn new() -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            rustdesk_id: None,
            status: SessionStatus::Pending,
            created_at: Utc::now(),
            name: None,
            message: None,
        }
    }
}

pub type SessionMap = Arc<RwLock<HashMap<String, Session>>>;
