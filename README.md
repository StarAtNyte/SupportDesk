# SupportDesk

A remote support platform built on [RustDesk](https://github.com/rustdesk/rustdesk), adding integrated support request workflow, admin dashboard, and self-hosted infrastructure.

## What's Different from RustDesk

- **"Request Support" button** built into the app — users can ask for help without leaving the screen
- **Admin Dashboard** — web-based panel showing all incoming support requests with one-click connect
- **Email Notifications** — admins get notified instantly when a user requests support
- **Self-Hosted Server** — full control over your data, no third-party dependencies
- **Custom Branding** — baked-in server configuration, ready for deployment

## Quick Start

### 1. Deploy the Server

```bash
# On your server (any Linux machine)
./deploy_server.sh <server-ip> <user> <password>

# Or with SSH key
./deploy_server.sh <server-ip> ubuntu ~/.ssh/key.pem
```

This installs `hbbs` (rendezvous) + `hbbr` (relay) via Docker and prints the server key.

### 2. Configure

Edit `deploy.env` with your server details:

```env
RENDEZVOUS_SERVER=your-server-ip
RELAY_SERVER=your-server-ip
SERVER_KEY=<key-from-step-1>
SUPPORT_SERVER_URL=http://your-server-ip:3030
```

### 3. Build the App

```bash
./build_custom.sh
```

This reads `deploy.env`, patches the source, builds the Rust library + Flutter app, and installs it.

### 4. Deploy Support Server

```bash
cd support-server
docker compose up -d
```

Dashboard: `http://your-server:3030/dashboard`

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   End User      │     │  Support Server  │     │   Admin/Agent   │
│   (SupportDesk) │     │   (Port 3030)    │     │   (Dashboard)   │
│                 │     │                 │     │                 │
│  [Request Help] │────▶│  /api/support-  │────▶│  Email + WS     │
│                 │     │  request        │     │  notification   │
└────────┬────────┘     └─────────────────┘     └────────┬────────┘
         │                                               │
         │         ┌─────────────────┐                   │
         │         │  RustDesk Server │                   │
         └────────▶│  hbbs + hbbr    │◀──────────────────┘
                   │  (Port 21116+)  │
                   └─────────────────┘
```

## Project Structure

```
├── deploy.env                  # Server configuration (edit this)
├── build_custom.sh             # Build script (reads deploy.env)
├── deploy_server.sh            # Server deployment script
├── libs/                       # Core Rust libraries
│   ├── hbb_common/src/config.rs  # Baked-in server defaults
│   └── scrap/                   # Screen capture
├── flutter/                    # Flutter UI
│   ├── lib/support_request.dart  # Support request dialog
│   ├── lib/desktop/             # Desktop-specific UI
│   └── lib/mobile/              # Mobile-specific UI
├── support-server/             # Support server (separate Rust app)
│   ├── src/main.rs              # Axum web server
│   ├── src/routes.rs            # API endpoints
│   ├── static/dashboard.html    # Admin dashboard
│   ├── static/widget.js         # Embeddable widget
│   ├── Dockerfile               # Container build
│   └── docker-compose.yml       # Easy deployment
└── .github/workflows/build.yml # CI/CD pipeline
```

## Support Server API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/support-request` | POST | Submit a support request |
| `/api/session` | POST | Create a new session |
| `/api/sessions` | GET | List all sessions |
| `/api/session/:id` | GET | Get session details |
| `/api/session/:id` | PATCH | Update session |
| `/api/session/:id` | DELETE | Close session |
| `/ws/agent` | WebSocket | Real-time updates |
| `/dashboard` | GET | Admin dashboard |
| `/widget.js` | GET | Embeddable widget |

## Embed Widget

Add a support button to any website:

```html
<script src="http://your-server:3030/widget.js"
  data-color="#2563eb"
  data-label="Get Support"
  data-position="right">
</script>
```

## License

This project is licensed under the [GNU Affero General Public License v3.0](LICENCE) — the same license as the upstream [RustDesk](https://github.com/rustdesk/rustdesk) project.

As required by AGPL-3.0, the complete source code is available in this repository. Users who receive compiled binaries have the right to request the corresponding source code.

## Credits

Built on [RustDesk](https://github.com/rustdesk/rustdesk) by the RustDesk team.
