# RustDesk Support Tool

A self-hosted remote support system. Clients visit your website, click **Remote Support**,
download a pre-configured installer, and their ID is shared with your team automatically.
Agents connect via a real-time dashboard.

```
Client (browser widget) ──► Support Server (Axum) ──► Agent (dashboard)
                                      │
                               RustDesk Server
                               (hbbs + hbbr)
```

---

## Folder Structure

```
support-server/
├── src/                  Rust/Axum backend
├── static/
│   ├── widget.js         Embeddable support button
│   ├── dashboard.html    Agent dashboard (real-time WebSocket)
│   └── SupportClient-Setup.exe   Built client installer (git-ignored)
├── installer/
│   ├── windows.nsi       NSIS script — builds the client .exe
│   └── build.sh          Reads .env, runs makensis, outputs to static/
├── client-deploy/
│   ├── install.ps1       Agent setup script (Windows)
│   └── install.sh        Agent setup script (Linux)
├── setup-server.sh       One-shot RustDesk server deploy (hbbs + hbbr)
├── .env                  Single config file — all settings live here
├── Dockerfile            Support server container
├── docker-compose.yml    Support server compose file
└── README.md
```

---

## Overview: Three Separate Things

| Component | What it is | How to run |
|---|---|---|
| **RustDesk Server** | Relay/rendezvous (hbbs + hbbr) | `setup-server.sh` |
| **Support Server** | Axum web app — widget, dashboard, downloads | `docker compose up -d` |
| **Client Installer** | Pre-configured `.exe` end-users download | `installer/build.sh` |

---

## Step 1 — Deploy the RustDesk Server

This sets up hbbs (rendezvous) and hbbr (relay) via Docker Compose and prints your public IP + server key.

```bash
chmod +x setup-server.sh

# Auto-detect environment
./setup-server.sh

# Or force a mode
./setup-server.sh --aws    # EC2 — reads IP from instance metadata
./setup-server.sh --local  # VPS / bare metal — reads IP from ifconfig.me
```

At the end you will see:

```
┌─ Client Configuration ──────────────────────────┐
│
│  ID Server    : 1.2.3.4
│  Relay Server : 1.2.3.4
│  Key          : <your-public-key>
│
└─────────────────────────────────────────────────┘
```

**Save these values.** You will need them in Step 2.

> The key is generated on first start and stored in `~/rustdesk-server/data/id_ed25519.pub`.
> To retrieve it later: `cat ~/rustdesk-server/data/id_ed25519.pub`

Open these ports in your firewall / AWS Security Group:

| Port | Protocol |
|------|----------|
| 21115 | TCP |
| 21116 | TCP + UDP |
| 21117 | TCP |
| 21118 | TCP |
| 21119 | TCP |

---

## Step 2 — Configure via `.env`

All settings live in a single `.env` file in `support-server/`. Create it:

```bash
cp .env.example .env   # or create from scratch
```

```env
# RustDesk server
SERVER_HOST=1.2.3.4                      # Your server IP or domain
SERVER_KEY=<your-public-key>             # From id_ed25519.pub
SERVER_URL=http://1.2.3.4:3030           # Full URL to your support server

# Gmail notifications (all three required to enable email)
GMAIL_USER=you@gmail.com
GMAIL_APP_PASSWORD=xxxx-xxxx-xxxx-xxxx  # App Password, not your login password
NOTIFY_EMAIL=agent@yourcompany.com       # Who receives the notification
```

`docker-compose.yml` and `installer/build.sh` both read from this file automatically — you only need to edit `.env`, nothing else.

---

## Step 3 — Deploy the Support Server

### Option A — Docker Compose (recommended)

```bash
# From the support-server/ directory
docker compose up -d

# Check logs
docker compose logs -f
```

### Option B — Build and run locally

```bash
cargo build --release
source .env && PORT=3030 ./target/release/rustdesk-support
```

Open port `3030 TCP` in your firewall.

**Verify it works:**
- Dashboard: `http://<your-server>:3030/dashboard`
- Test page:  `http://<your-server>:3030/test`

---

## Step 4 — Build the Client Installer (Windows .exe)

The client installer is an NSIS-based `.exe` that:
1. Installs RustDesk silently
2. Writes the pre-configured server + key into `RustDesk2.toml`
3. Launches RustDesk and reads the generated ID
4. POSTs the ID directly to the support server — no copy-pasting needed
5. Shows a finish screen with the ID for reference

**Requirements:** NSIS (`sudo apt-get install -y nsis`)

```bash
cd installer/
./build.sh
# Output: ../static/SupportClient-Setup.exe
```

The `.exe` is automatically served by the support server at `/download/windows-installer`.

> Re-run `build.sh` any time you update `.env` (e.g. after changing the server key).

---

## Step 5 — Set Up Agents

Agents are support staff who receive and handle sessions from the dashboard.

### Windows agent

```powershell
# Right-click → Run as Administrator
.\client-deploy\install.ps1
```

### Linux agent

```bash
chmod +x client-deploy/install.sh
./client-deploy/install.sh
```

Both scripts download and install RustDesk with the correct server and key config.

Agents then open the dashboard in their browser and keep it open while on duty:

```
http://<your-server>:3030/dashboard
```

---

## Step 6 — Embed the Widget on Your Website

Drop a single `<script>` tag anywhere on your page:

```html
<script src="http://<your-server>:3030/widget.js"></script>
```

A **Remote Support** button appears at the bottom-right. Works on any stack — React, Vue, WordPress, plain HTML.

### Widget Customisation

All appearance options are set via `data-*` attributes on the script tag — no config files to edit:

```html
<script src="http://<your-server>:3030/widget.js"
  data-color="#7c3aed"
  data-label="Talk to Us"
  data-position="left"
  data-bottom="32"
  data-side="32">
</script>
```

| Attribute | Default | Description |
|---|---|---|
| `data-color` | `#2563eb` | Button and modal accent color — any valid CSS color (`#hex`, `rgb()`, named) |
| `data-label` | `Remote Support` | Text shown on the floating button |
| `data-position` | `right` | Which side of the screen: `"left"` or `"right"` |
| `data-bottom` | `24` | Distance from the bottom edge, in px |
| `data-side` | `24` | Distance from the left/right edge, in px |

All attributes are optional — omit any you don't need and the default applies.

---

## How a Support Session Works

1. Client clicks **Remote Support** on your website
2. Widget creates a session and the installer downloads automatically
3. Client runs `SupportClient-Setup.exe` — RustDesk installs silently
4. Installer reads the RustDesk ID and **POSTs it directly to the support server**
5. Widget polls every 3 seconds; once the session is claimed it shows "Agent on the way!" then auto-closes
6. Agent receives a **Gmail notification** with the ID and a link to the dashboard
7. Agent dashboard also updates in real-time via WebSocket
8. Agent clicks **Connect** in the dashboard — RustDesk opens to the client's screen
9. Client clicks **Accept** — session begins

### Widget states

| State | Trigger |
|---|---|
| Waiting for installer… | Default after download starts |
| Agent on the way! *(auto-closes in 8s)* | Installer ran and claimed a session |
| Request received! | No claim after 20 minutes — team was still notified by email |
| Something went wrong | Session lost (e.g. server restarted) — user can try again |

---

## Gmail Email Notifications

When the installer runs and reports its ID, the support server sends an email containing the RustDesk ID and a link directly to the agent dashboard.

Gmail requires an **App Password** — your regular Gmail password will not work.

1. Go to [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)
2. Create an app password (name it anything, e.g. "Support Server")
3. Add the 16-character password to `.env`:

```env
GMAIL_USER=you@gmail.com
GMAIL_APP_PASSWORD=xxxx-xxxx-xxxx-xxxx
NOTIFY_EMAIL=agent@yourcompany.com
```

If any of the three vars are missing the server starts fine but skips email sending.

> **Google Workspace accounts:** App Passwords may be disabled by your admin.
> Check under *Manage your Google Account → Security → 2-Step Verification → App passwords*.

---

## HTTPS Setup (required if your site uses HTTPS)

Browsers block mixed content — if your website is on `https://`, the support server must also be HTTPS.

```bash
sudo apt-get install -y nginx certbot python3-certbot-nginx

sudo tee /etc/nginx/sites-available/support << 'EOF'
server {
    server_name support.yourdomain.com;
    location / {
        proxy_pass http://localhost:3030;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
}
EOF

sudo ln -s /etc/nginx/sites-available/support /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d support.yourdomain.com
```

Then update `SERVER_URL` in `.env` and the widget embed to use `https://support.yourdomain.com`.

---

## Production Checklist

- [ ] Run `setup-server.sh` — note the IP and key printed at the end
- [ ] Fill in `.env` with `SERVER_HOST`, `SERVER_KEY`, `SERVER_URL`, and Gmail vars
- [ ] Build client installer: `cd installer && ./build.sh`
- [ ] Deploy support server: `docker compose up -d`
- [ ] Open port `3030 TCP` in firewall
- [ ] Set up Nginx + HTTPS if your site uses `https://` (and update `SERVER_URL` in `.env`)
- [ ] Run agent install script on each support machine
- [ ] Embed `widget.js` on your website
- [ ] Test full flow: widget click → auto-download → install → widget shows "Agent on the way!" → email arrives

---

## Useful Commands

```bash
# RustDesk server (hbbs/hbbr)
docker compose -f ~/rustdesk-server/docker-compose.yml logs -f
docker compose -f ~/rustdesk-server/docker-compose.yml restart

# Support server
docker compose logs -f
docker compose restart

# Rebuild after code changes
docker compose build && docker compose up -d

# Rebuild installer after .env changes
cd installer && ./build.sh

# Get server key at any time
cat ~/rustdesk-server/data/id_ed25519.pub
```
