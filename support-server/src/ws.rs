use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        State,
    },
    response::IntoResponse,
};
use serde_json::json;

use crate::AppState;

pub async fn agent_ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
) -> impl IntoResponse {
    ws.on_upgrade(|socket| handle_socket(socket, state))
}

async fn handle_socket(mut socket: WebSocket, state: AppState) {
    let mut rx = state.tx.subscribe();

    // Send all current sessions immediately on connect
    {
        let sessions = state.sessions.read().await;
        let all: Vec<_> = sessions.values().collect();
        let msg = json!({ "type": "initial", "sessions": all }).to_string();
        if socket.send(Message::Text(msg)).await.is_err() {
            return;
        }
    }

    loop {
        tokio::select! {
            event = rx.recv() => {
                match event {
                    Ok(text) => {
                        if socket.send(Message::Text(text)).await.is_err() {
                            break;
                        }
                    }
                    Err(_) => break,
                }
            }
            msg = socket.recv() => {
                match msg {
                    Some(Ok(Message::Close(_))) | None => break,
                    _ => {}
                }
            }
        }
    }
}
