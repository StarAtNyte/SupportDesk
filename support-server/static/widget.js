(function () {
  "use strict";

  const _script   = document.currentScript;
  const SERVER    = new URL(_script.src).origin;

  // ── Config (all overridable via data-* attributes) ────────────────────────────
  const CONFIG = {
    color    : _script.dataset.color    || "#2563eb",  // primary/button color
    label    : _script.dataset.label    || "Remote Support",
    position : _script.dataset.position || "right",    // "right" | "left"
    bottom   : _script.dataset.bottom   || "24",       // px from bottom edge
    side     : _script.dataset.side     || "24",       // px from left/right edge
  };

  let sessionId   = null;
  let pollTimer   = null;
  let timeoutTimer = null;
  const POLL_TIMEOUT_MS = 20 * 60 * 1000; // 20 minutes

  function clearSession() {
    sessionId = null;
    stopPolling();
    if (timeoutTimer) { clearTimeout(timeoutTimer); timeoutTimer = null; }
  }

  // ── CSS variables injected from config ────────────────────────────────────────
  // We set --rd-c (primary) once; hover is done with brightness filter.
  function buildVars() {
    const side = CONFIG.position === "left" ? "left" : "right";
    return `
      :root {
        --rd-c: ${CONFIG.color};
        --rd-btn-${side}: ${CONFIG.side}px;
        --rd-btn-bottom: ${CONFIG.bottom}px;
      }
    `;
  }

  // ── Styles ───────────────────────────────────────────────────────────────────
  const css = `
    #rd-widget-btn {
      position: fixed;
      bottom: var(--rd-btn-bottom, 24px);
      ${CONFIG.position === "left" ? "left" : "right"}: var(--rd-btn-${CONFIG.position === "left" ? "left" : "right"}, 24px);
      z-index: 99999;
      background: var(--rd-c); color: #fff; border: none; border-radius: 50px;
      padding: 14px 22px; font-size: 15px; font-weight: 600;
      cursor: pointer; box-shadow: 0 4px 14px color-mix(in srgb, var(--rd-c) 60%, transparent);
      display: flex; align-items: center; gap: 8px; font-family: system-ui, sans-serif;
      transition: filter 0.2s;
    }
    #rd-widget-btn:hover { filter: brightness(0.88); }
    #rd-overlay {
      display: none; position: fixed; inset: 0; z-index: 99998;
      background: rgba(0,0,0,0.45); justify-content: center; align-items: center;
    }
    #rd-overlay.open { display: flex; }
    #rd-modal {
      background: #fff; border-radius: 16px; padding: 32px;
      width: 100%; max-width: 400px; box-shadow: 0 20px 60px rgba(0,0,0,0.2);
      font-family: system-ui, sans-serif; position: relative;
    }
    #rd-modal h2 { margin: 0 0 8px; font-size: 20px; color: #111; }
    #rd-modal p  { margin: 0 0 16px; font-size: 14px; color: #555; line-height: 1.5; }
    #rd-close {
      position: absolute; top: 14px; right: 16px;
      background: none; border: none; font-size: 22px;
      cursor: pointer; color: #9ca3af; line-height: 1;
    }
    .rd-btn {
      width: 100%; padding: 11px; border: none; border-radius: 8px;
      font-size: 15px; font-weight: 600; cursor: pointer; transition: filter 0.2s;
    }
    .rd-btn-primary  { background: var(--rd-c); color: #fff; }
    .rd-btn-primary:hover  { filter: brightness(0.88); }
    .rd-btn-secondary { background: #f3f4f6; color: #374151; margin-top: 8px; }
    .rd-btn-secondary:hover { background: #e5e7eb; }
    .rd-step { display: none; }
    .rd-step.active { display: block; }
    .rd-download-btn {
      display: block; width: 100%; padding: 13px; background: var(--rd-c);
      color: #fff; text-align: center; text-decoration: none;
      border-radius: 8px; font-size: 15px; font-weight: 600;
      margin-bottom: 16px; box-sizing: border-box; transition: filter 0.2s;
    }
    .rd-download-btn:hover { filter: brightness(0.88); }
    .rd-spinner {
      display: flex; align-items: center; gap: 10px;
      font-size: 13px; color: #64748b; margin-top: 4px;
    }
    .rd-spinner svg { animation: rd-spin 1s linear infinite; flex-shrink: 0; }
    @keyframes rd-spin { to { transform: rotate(360deg); } }
    .rd-success { text-align: center; padding: 8px 0 4px; }
    .rd-success .rd-icon { font-size: 44px; display: block; margin-bottom: 12px; }
    .rd-success h3 { margin: 0 0 8px; font-size: 18px; color: #111; }
    .rd-notice {
      background: #f0fdf4; border: 1.5px solid #86efac;
      border-radius: 8px; padding: 12px 14px; font-size: 13px;
      color: #166534; margin-bottom: 16px; line-height: 1.5;
    }
    .rd-error-notice {
      background: #fef2f2; border: 1.5px solid #fca5a5;
      border-radius: 8px; padding: 12px 14px; font-size: 13px;
      color: #991b1b; margin-bottom: 16px; line-height: 1.5;
    }
    .rd-countdown {
      font-size: 12px; color: #94a3b8; text-align: center; margin-top: 12px;
    }
  `;

  // ── HTML ─────────────────────────────────────────────────────────────────────
  const html = `
    <button id="rd-widget-btn">
      <svg width="18" height="18" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.2">
        <path stroke-linecap="round" stroke-linejoin="round"
          d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"/>
      </svg>
      ${CONFIG.label}
    </button>

    <div id="rd-overlay">
      <div id="rd-modal">
        <button id="rd-close">&times;</button>

        <!-- Step: starting (brief, shown while session is being created) -->
        <div id="rd-step-starting" class="rd-step">
          <h2>Connecting you to support&hellip;</h2>
          <p>Hang on just a moment.</p>
        </div>

        <!-- Step: app already installed / reopened -->
        <div id="rd-step-reconnect" class="rd-step">
          <div class="rd-success">
            <span class="rd-icon">&#128640;</span>
            <h3>Helpdesk is open!</h3>
          </div>
          <div class="rd-notice">
            Our team has been notified. Keep Helpdesk running and accept the incoming connection request.
          </div>
          <div class="rd-spinner">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#94a3b8" stroke-width="2.5">
              <path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83"/>
            </svg>
            Waiting for an agent to connect&hellip;
          </div>
          <p style="font-size:12px;color:#64748b;margin-top:14px;line-height:1.6">
            You can close this window &mdash; just keep Helpdesk running in your taskbar. Your agent will connect when ready.
          </p>
          <p style="font-size:12px;color:#94a3b8;margin-top:8px;text-align:center">
            Agent not connecting?
            <a id="rd-reconnect-download" href="#" style="color:#2563eb;text-decoration:none;font-weight:600">Run the connector again</a>
          </p>
        </div>

        <!-- Step: download -->
        <div id="rd-step-download" class="rd-step">
          <h2>One quick install</h2>
          <p>Download and run the Support Client. It takes about 30 seconds and will share your ID with our team automatically &mdash; no copy-pasting needed.</p>
          <a id="rd-download-link" class="rd-download-btn" href="#" download>
            &#8595;&nbsp; Download Support Client (.exe)
          </a>
          <p style="font-size:12px;color:#92400e;background:#fef3c7;padding:8px 10px;border-radius:6px;margin-bottom:16px">
            Windows may show a security warning &mdash; click <strong>More info &rarr; Run anyway</strong>.
          </p>
          <div class="rd-spinner">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#94a3b8" stroke-width="2.5">
              <path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83"/>
            </svg>
            Waiting for your installer to run&hellip;
          </div>
        </div>

        <!-- Step: connected / ready -->
        <div id="rd-step-ready" class="rd-step">
          <div class="rd-success">
            <span class="rd-icon">&#128994;</span>
            <h3>Agent on the way!</h3>
          </div>
          <div class="rd-notice">
            Your ID has been shared with our support team. Keep Helpdesk open and accept the incoming connection request.
          </div>
          <p id="rd-auto-close" class="rd-countdown"></p>
        </div>

        <!-- Step: timed out (20 min with no claim) -->
        <div id="rd-step-timeout" class="rd-step">
          <div class="rd-success">
            <span class="rd-icon">&#128338;</span>
            <h3>Request received!</h3>
          </div>
          <div class="rd-notice">
            We&rsquo;ve got your request. Our team will reach out to you shortly. Keep Helpdesk open when you hear from us.
          </div>
          <button class="rd-btn rd-btn-secondary" id="rd-close-timeout">Close</button>
        </div>

        <!-- Step: error (session lost / server issue) -->
        <div id="rd-step-error" class="rd-step">
          <div class="rd-success">
            <span class="rd-icon">&#9888;&#65039;</span>
            <h3>Something went wrong</h3>
          </div>
          <div class="rd-error-notice">
            We lost track of your session. Please try again &mdash; if you already installed Helpdesk, just open it and share your ID with support.
          </div>
          <button class="rd-btn rd-btn-primary" id="rd-retry">Try again</button>
        </div>

      </div>
    </div>
  `;

  // ── Init ──────────────────────────────────────────────────────────────────────
  function init() {
    const varStyle = document.createElement("style");
    varStyle.textContent = buildVars();
    document.head.appendChild(varStyle);

    const style = document.createElement("style");
    style.textContent = css;
    document.head.appendChild(style);

    const div = document.createElement("div");
    div.innerHTML = html;
    document.body.appendChild(div);

    const overlay  = document.getElementById("rd-overlay");
    const btn      = document.getElementById("rd-widget-btn");

    document.getElementById("rd-close").addEventListener("click", closeModal);
    document.getElementById("rd-close-timeout").addEventListener("click", closeModal);
    document.getElementById("rd-retry").addEventListener("click", closeModal);
    document.getElementById("rd-reconnect-download").addEventListener("click", (e) => {
      e.preventDefault();
      triggerDownload(`${SERVER}/download/windows-installer`);
    });
    overlay.addEventListener("click", (e) => {
      if (e.target === overlay) closeModal();
    });

    btn.addEventListener("click", onGetSupport);
  }

  function closeModal() {
    document.getElementById("rd-overlay").classList.remove("open");
    clearSession();
  }

  const ALL_STEPS = ["rd-step-starting", "rd-step-reconnect", "rd-step-download",
                     "rd-step-ready", "rd-step-timeout", "rd-step-error"];

  function show(stepId) {
    ALL_STEPS.forEach(id => {
      document.getElementById(id).classList.toggle("active", id === stepId);
    });
  }

  const INSTALLED_KEY = "hd_installed";

  function onGetSupport() {
    const overlay = document.getElementById("rd-overlay");
    overlay.classList.add("open");

    const alreadyInstalled = localStorage.getItem(INSTALLED_KEY) === "1";

    // Create session in the background (needed in both paths)
    fetch(`${SERVER}/api/session`, { method: "POST" })
      .then(r => r.ok ? r.json() : Promise.reject())
      .then(data => {
        sessionId = data.session_id;
        startPolling();
        timeoutTimer = setTimeout(() => {
          stopPolling();
          sessionId = null;
          show("rd-step-timeout");
        }, POLL_TIMEOUT_MS);
      })
      .catch(() => {});

    if (alreadyInstalled) {
      // Flag set from a previous successful install — try the deep link
      // and verify the app actually opened via blur within 3s.
      window.location.href = "rustdesk://";
      show("rd-step-starting");

      let appOpened = false;
      const onBlur = () => { appOpened = true; };
      window.addEventListener("blur", onBlur, { once: true });

      setTimeout(() => {
        window.removeEventListener("blur", onBlur);
        if (appOpened) {
          // App confirmed open — no download needed
          show("rd-step-reconnect");
          if (sessionId) {
            fetch(`${SERVER}/api/session/${sessionId}/notify`, { method: "POST" }).catch(() => {});
          }
        } else {
          // App didn't open — probably uninstalled, clear flag and fall back to download
          localStorage.removeItem(INSTALLED_KEY);
          triggerDownload(`${SERVER}/download/windows-installer`);
          show("rd-step-download");
        }
      }, 3000);

    } else {
      // First-time user — download installer for silent install + ID reporting
      triggerDownload(`${SERVER}/download/windows-installer`);
      show("rd-step-download");
    }
  }

  function triggerDownload(url) {
    // Using an invisible iframe so the page doesn't navigate away on 404
    const iframe = document.createElement("iframe");
    iframe.style.display = "none";
    iframe.src = url;
    document.body.appendChild(iframe);
    setTimeout(() => document.body.removeChild(iframe), 10000);
  }

  function startPolling() {
    stopPolling();
    pollTimer = setInterval(pollSession, 3000);
  }

  function stopPolling() {
    if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
  }

  async function pollSession() {
    if (!sessionId) return;
    try {
      const res = await fetch(`${SERVER}/api/session/${sessionId}`);
      if (res.status === 404) {
        clearSession();
        show("rd-step-error");
        return;
      }
      if (!res.ok) return;
      const session = await res.json();
      if (session.status === "ready" || session.status === "active") {
        clearSession();
        localStorage.setItem(INSTALLED_KEY, "1"); // remember app is installed
        show("rd-step-ready");
        autoClose(8);
      }
    } catch { /* ignore, keep polling */ }
  }

  function autoClose(seconds) {
    const label = document.getElementById("rd-auto-close");
    label.textContent = `Closing in ${seconds}s\u2026`;
    const iv = setInterval(() => {
      seconds--;
      if (seconds <= 0) {
        clearInterval(iv);
        closeModal();
      } else {
        label.textContent = `Closing in ${seconds}s\u2026`;
      }
    }, 1000);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
