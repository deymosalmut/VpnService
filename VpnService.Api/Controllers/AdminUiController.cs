using Microsoft.AspNetCore.Mvc;

namespace VpnService.Api.Controllers;

[ApiController]
public class AdminUiController : ControllerBase
{
    private const string AdminHtml = """
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>VPN Service Admin</title>
  <style>
    :root {
      --bg: #efe8dc;
      --panel: #ffffff;
      --ink: #1e1b16;
      --muted: #5c564d;
      --accent: #1f5f7a;
      --accent-2: #b0552f;
      --border: #d8d0c4;
      --danger: #b00020;
      --shadow: 0 14px 40px rgba(0, 0, 0, 0.08);
      --mono: "Courier New", Courier, monospace;
      --sans: "Trebuchet MS", "Verdana", sans-serif;
      --serif: "Georgia", "Times New Roman", serif;
    }

    * { box-sizing: border-box; }
    body {
      margin: 0;
      color: var(--ink);
      font-family: var(--sans);
      background:
        radial-gradient(1200px 700px at 15% -10%, #fff5df 0%, rgba(255, 245, 223, 0) 55%),
        radial-gradient(800px 500px at 90% 10%, #e6f0f3 0%, rgba(230, 240, 243, 0) 60%),
        linear-gradient(180deg, #f2ece2 0%, #e6ded2 100%);
      min-height: 100vh;
      padding: 24px 16px 40px;
    }

    .wrap {
      max-width: 980px;
      margin: 0 auto;
      animation: rise 520ms ease-out;
    }

    header {
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      gap: 16px;
      margin-bottom: 18px;
      flex-wrap: wrap;
    }

    h1 {
      font-family: var(--serif);
      font-size: 28px;
      margin: 0;
      letter-spacing: 0.4px;
    }

    h2 {
      font-family: var(--serif);
      font-size: 18px;
      margin: 0;
      letter-spacing: 0.3px;
    }

    .tagline {
      color: var(--muted);
      font-size: 14px;
    }

    .warning {
      font-size: 12px;
      color: var(--danger);
      border: 1px dashed var(--danger);
      padding: 6px 10px;
      border-radius: 999px;
      background: rgba(176, 0, 32, 0.06);
      white-space: nowrap;
    }

    .panel {
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 18px;
      box-shadow: var(--shadow);
    }

    .stack {
      display: grid;
      gap: 16px;
    }

    label {
      font-size: 12px;
      color: var(--muted);
      text-transform: uppercase;
      letter-spacing: 0.06em;
    }

    input {
      width: 100%;
      padding: 10px 12px;
      border-radius: 10px;
      border: 1px solid var(--border);
      font-size: 14px;
      font-family: var(--sans);
      background: #fcfbf9;
    }

    textarea {
      width: 100%;
      min-height: 180px;
      padding: 12px;
      border-radius: 12px;
      border: 1px solid var(--border);
      font-size: 12px;
      font-family: var(--mono);
      background: #fcfbf9;
      resize: vertical;
    }

    .row {
      display: flex;
      gap: 12px;
      flex-wrap: wrap;
    }

    .row > * {
      flex: 1 1 200px;
    }

    button {
      border: none;
      border-radius: 999px;
      padding: 10px 16px;
      font-size: 14px;
      cursor: pointer;
      transition: transform 120ms ease, box-shadow 120ms ease;
      font-family: var(--sans);
    }

    button.primary {
      background: var(--accent);
      color: #fff;
      box-shadow: 0 6px 18px rgba(31, 95, 122, 0.3);
    }

    button.secondary {
      background: #fff;
      color: var(--accent);
      border: 1px solid var(--accent);
    }

    button.warn {
      background: var(--accent-2);
      color: #fff;
      box-shadow: 0 6px 18px rgba(176, 85, 47, 0.25);
    }

    button:active {
      transform: translateY(1px);
      box-shadow: none;
    }

    button:disabled {
      opacity: 0.6;
      cursor: not-allowed;
      box-shadow: none;
    }

    .button-link {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      text-decoration: none;
      border-radius: 999px;
      padding: 10px 16px;
      font-size: 14px;
      font-family: var(--sans);
      cursor: pointer;
      transition: transform 120ms ease, box-shadow 120ms ease;
    }

    .button-link.secondary {
      background: #fff;
      color: var(--accent);
      border: 1px solid var(--accent);
    }

    .status {
      font-size: 13px;
      padding: 4px 10px;
      border-radius: 999px;
      display: inline-block;
      background: #f1eee8;
      color: var(--muted);
    }

    .status.ok {
      background: rgba(31, 95, 122, 0.12);
      color: var(--accent);
    }

    .output {
      font-family: var(--mono);
      background: #101316;
      color: #e7e1d6;
      border-radius: 12px;
      padding: 16px;
      min-height: 160px;
      max-height: 360px;
      overflow: auto;
      white-space: pre-wrap;
      border: 1px solid rgba(0, 0, 0, 0.2);
    }

    .output.error {
      border-color: rgba(176, 0, 32, 0.6);
      color: #f1c4c9;
    }

    .error-text {
      color: var(--danger);
      font-size: 12px;
    }

    .mono-inline {
      font-family: var(--mono);
      font-size: 12px;
      word-break: break-all;
    }

    .peer-grid {
      display: grid;
      gap: 16px;
      grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
      align-items: start;
    }

    .qr-box {
      background: #f7f3ea;
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 12px;
      display: flex;
      align-items: center;
      justify-content: center;
    }

    .qr-box img {
      width: 220px;
      max-width: 100%;
      height: auto;
    }

    details {
      border: 1px dashed var(--border);
      border-radius: 12px;
      padding: 10px 12px;
      background: #fbf8f2;
    }

    summary {
      cursor: pointer;
      font-size: 12px;
      color: var(--muted);
      text-transform: uppercase;
      letter-spacing: 0.06em;
    }

    @keyframes rise {
      from { opacity: 0; transform: translateY(12px); }
      to { opacity: 1; transform: translateY(0); }
    }

    @media (max-width: 720px) {
      header { align-items: flex-start; }
      h1 { font-size: 24px; }
      .peer-grid { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <div class="wrap">
    <header>
      <div>
        <h1>VPN Service Admin</h1>
        <div class="tagline">Minimal UI for auth + WireGuard admin endpoints.</div>
      </div>
      <div class="warning">Do not use on untrusted machines.</div>
    </header>

    <div class="panel stack">
      <form id="login-form" class="stack">
        <div class="row">
          <div>
            <label for="username">Username</label>
            <input id="username" name="username" autocomplete="username" required>
          </div>
          <div>
            <label for="password">Password</label>
            <input id="password" name="password" type="password" autocomplete="current-password" required>
          </div>
        </div>
        <div class="row" style="align-items: center;">
          <button class="primary" type="submit">Login</button>
          <span id="token-status" class="status">Not logged in</span>
        </div>
      </form>

      <div class="row">
        <button id="btn-health" class="secondary" type="button">Health</button>
        <button id="btn-wg-state" class="secondary" type="button">WG State</button>
        <button id="btn-reconcile" class="secondary" type="button">Reconcile (dry-run)</button>
        <button id="btn-logout" class="warn" type="button">Logout</button>
      </div>

      <section id="create-peer" class="stack">
        <div class="row" style="align-items: center;">
          <h2>Create WireGuard peer</h2>
          <span id="peer-status" class="status">Idle</span>
        </div>

        <form id="peer-form" class="stack">
          <div class="row">
            <div>
              <label for="peer-name">Name</label>
              <input id="peer-name" placeholder="iphone-alex" required>
            </div>
            <div>
              <label for="peer-dns">DNS (optional)</label>
              <input id="peer-dns" placeholder="1.1.1.1">
            </div>
          </div>

          <details>
            <summary>Advanced</summary>
            <div class="row" style="margin-top: 10px;">
              <div>
                <label for="peer-endpoint-host">Endpoint host</label>
                <input id="peer-endpoint-host" placeholder="vpn.example.com">
              </div>
              <div>
                <label for="peer-endpoint-port">Endpoint port</label>
                <input id="peer-endpoint-port" type="number" min="1" max="65535" placeholder="51820">
              </div>
            </div>
          </details>

          <div class="row" style="align-items: center;">
            <button id="create-peer-btn" class="primary" type="submit">Create peer</button>
            <button id="peer-clear-btn" class="secondary" type="button">Clear</button>
            <span id="peer-error" class="error-text" role="alert"></span>
          </div>
        </form>

        <div id="peer-result" class="stack" style="display: none;">
          <div class="peer-grid">
            <div>
              <label>QR Code</label>
              <div class="qr-box">
                <img id="peer-qr" alt="WireGuard QR code">
              </div>
            </div>
            <div class="stack">
              <div>
                <label>Public key</label>
                <div id="peer-public-key" class="mono-inline"></div>
              </div>
              <div class="row">
                <div>
                  <label>Address</label>
                  <div id="peer-address" class="mono-inline"></div>
                </div>
                <div>
                  <label>Interface</label>
                  <div id="peer-iface" class="mono-inline"></div>
                </div>
              </div>
              <div class="row">
                <a id="peer-config-download" class="button-link secondary" href="#" download>Download config</a>
                <button id="peer-copy-btn" class="secondary" type="button">Copy config</button>
              </div>
            </div>
          </div>
          <div>
            <label for="peer-config">Config</label>
            <textarea id="peer-config" readonly></textarea>
          </div>
        </div>
      </section>

      <div>
        <label for="output">Response</label>
        <pre id="output" class="output">Ready.</pre>
      </div>
    </div>
  </div>

  <script>
    (function () {
      const baseUrl = window.location.origin;
      const tokenKey = "vpnservice.admin.accessToken";

      const outputEl = document.getElementById("output");
      const statusEl = document.getElementById("token-status");
      const loginForm = document.getElementById("login-form");
      const healthBtn = document.getElementById("btn-health");
      const wgStateBtn = document.getElementById("btn-wg-state");
      const reconcileBtn = document.getElementById("btn-reconcile");
      const logoutBtn = document.getElementById("btn-logout");
      const peerForm = document.getElementById("peer-form");
      const peerNameInput = document.getElementById("peer-name");
      const peerDnsInput = document.getElementById("peer-dns");
      const peerEndpointHostInput = document.getElementById("peer-endpoint-host");
      const peerEndpointPortInput = document.getElementById("peer-endpoint-port");
      const peerStatusEl = document.getElementById("peer-status");
      const peerErrorEl = document.getElementById("peer-error");
      const peerResultEl = document.getElementById("peer-result");
      const peerQrEl = document.getElementById("peer-qr");
      const peerPublicKeyEl = document.getElementById("peer-public-key");
      const peerAddressEl = document.getElementById("peer-address");
      const peerIfaceEl = document.getElementById("peer-iface");
      const peerConfigEl = document.getElementById("peer-config");
      const peerDownloadEl = document.getElementById("peer-config-download");
      const peerCopyBtn = document.getElementById("peer-copy-btn");
      const peerClearBtn = document.getElementById("peer-clear-btn");
      const peerCreateBtn = document.getElementById("create-peer-btn");
      let peerConfigUrl = "";

      function setOutput(text, isError) {
        outputEl.textContent = text || "";
        outputEl.classList.toggle("error", Boolean(isError));
      }

      function getToken() {
        return sessionStorage.getItem(tokenKey) || "";
      }

      function setToken(token) {
        if (token) {
          sessionStorage.setItem(tokenKey, token);
        } else {
          sessionStorage.removeItem(tokenKey);
        }
        updateStatus();
      }

      function updateStatus() {
        const hasToken = Boolean(getToken());
        statusEl.textContent = hasToken ? "Logged in" : "Not logged in";
        statusEl.classList.toggle("ok", hasToken);
        setPeerFormEnabled(hasToken);
        setPeerStatus(hasToken ? "Ready" : "Login required", hasToken);
      }

      function setPeerFormEnabled(enabled) {
        const disabled = !enabled;
        peerNameInput.disabled = disabled;
        peerDnsInput.disabled = disabled;
        peerEndpointHostInput.disabled = disabled;
        peerEndpointPortInput.disabled = disabled;
        peerCreateBtn.disabled = disabled;
      }

      function setPeerStatus(text, ok) {
        peerStatusEl.textContent = text || "";
        peerStatusEl.classList.toggle("ok", Boolean(ok));
      }

      function setPeerError(message) {
        peerErrorEl.textContent = message || "";
      }

      function clearPeerResult() {
        if (peerConfigUrl) {
          URL.revokeObjectURL(peerConfigUrl);
          peerConfigUrl = "";
        }

        peerResultEl.style.display = "none";
        peerQrEl.removeAttribute("src");
        peerConfigEl.value = "";
        peerPublicKeyEl.textContent = "";
        peerAddressEl.textContent = "";
        peerIfaceEl.textContent = "";
        peerDownloadEl.removeAttribute("href");
      }

      function sanitizeFileName(name) {
        const trimmed = (name || "").trim();
        const safe = trimmed.replace(/[^a-zA-Z0-9._-]+/g, "_");
        return safe || "peer";
      }

      function updateDownloadLink(name, config) {
        if (peerConfigUrl) {
          URL.revokeObjectURL(peerConfigUrl);
        }
        const blob = new Blob([config], { type: "text/plain" });
        peerConfigUrl = URL.createObjectURL(blob);
        peerDownloadEl.href = peerConfigUrl;
        peerDownloadEl.download = sanitizeFileName(name) + ".conf";
      }

      async function copyPeerConfig() {
        const config = peerConfigEl.value;
        if (!config) {
          setPeerError("No config to copy.");
          return;
        }

        try {
          if (navigator.clipboard && window.isSecureContext) {
            await navigator.clipboard.writeText(config);
          } else {
            peerConfigEl.focus();
            peerConfigEl.select();
            peerConfigEl.setSelectionRange(0, peerConfigEl.value.length);
            document.execCommand("copy");
            peerConfigEl.blur();
          }
          setPeerError("");
          setPeerStatus("Config copied", true);
        } catch (err) {
          setPeerError("Failed to copy config.");
          setPeerStatus("Error", false);
        }
      }

      async function handleCreatePeer(event) {
        event.preventDefault();
        setPeerError("");

        const token = getToken();
        if (!token) {
          setPeerStatus("Login required", false);
          setPeerError("Unauthorized, please login.");
          return;
        }

        const name = peerNameInput.value.trim();
        if (!name) {
          setPeerError("Name is required.");
          return;
        }

        const payload = { name: name };
        const dns = peerDnsInput.value.trim();
        const endpointHost = peerEndpointHostInput.value.trim();
        const endpointPortRaw = peerEndpointPortInput.value.trim();

        if (dns) {
          payload.dns = dns;
        }

        if (endpointHost) {
          payload.endpointHost = endpointHost;
        }

        if (endpointPortRaw) {
          const port = Number(endpointPortRaw);
          if (!Number.isInteger(port) || port < 1 || port > 65535) {
            setPeerError("Endpoint port must be between 1 and 65535.");
            return;
          }
          payload.endpointPort = port;
        }

        try {
          setPeerStatus("Creating...", false);
          clearPeerResult();

          const response = await fetch(baseUrl + "/api/v1/admin/wg/peer", {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "Authorization": "Bearer " + token
            },
            body: JSON.stringify(payload)
          });

          if (response.status === 401) {
            setPeerStatus("Login required", false);
            setPeerError("Unauthorized, please login.");
            return;
          }

          const body = await readBody(response);
          if (!response.ok) {
            setPeerStatus("Error", false);
            setPeerError(body.text || "Peer creation failed.");
            return;
          }

          if (!body.json) {
            setPeerStatus("Error", false);
            setPeerError("Unexpected response format.");
            return;
          }

          const data = body.json;
          if (!data.qrDataUrl || !data.config) {
            setPeerStatus("Error", false);
            setPeerError("Response missing config or QR.");
            return;
          }

          peerQrEl.src = data.qrDataUrl;
          peerConfigEl.value = data.config;
          peerPublicKeyEl.textContent = data.publicKey || "";
          peerAddressEl.textContent = data.address || "";
          peerIfaceEl.textContent = data.iface || "";
          updateDownloadLink(name, data.config);
          peerResultEl.style.display = "grid";

          setPeerStatus("Ready", true);
        } catch (err) {
          setPeerStatus("Error", false);
          setPeerError(String(err));
        }
      }

      async function readBody(response) {
        const contentType = response.headers.get("content-type") || "";
        if (contentType.includes("application/json")) {
          const data = await response.json();
          return { text: JSON.stringify(data, null, 2), json: data };
        }
        const text = await response.text();
        return { text, json: null };
      }

      async function handleHealth() {
        try {
          setOutput("Calling /health...");
          const response = await fetch(baseUrl + "/health");
          const body = await readBody(response);
          setOutput(body.text, !response.ok);
        } catch (err) {
          setOutput(String(err), true);
        }
      }

      async function callAuthorized(path) {
        const token = getToken();
        if (!token) {
          setOutput("Unauthorized, please login", true);
          return;
        }

        try {
          setOutput("Calling " + path + "...");
          const response = await fetch(baseUrl + path, {
            headers: {
              "Authorization": "Bearer " + token
            }
          });

          if (response.status === 401) {
            setOutput("Unauthorized, please login", true);
            return;
          }

          const body = await readBody(response);
          setOutput(body.text, !response.ok);
        } catch (err) {
          setOutput(String(err), true);
        }
      }

      loginForm.addEventListener("submit", async function (event) {
        event.preventDefault();

        const username = document.getElementById("username").value.trim();
        const password = document.getElementById("password").value;

        if (!username || !password) {
          setOutput("Username and password are required.", true);
          return;
        }

        try {
          setOutput("Logging in...");
          const response = await fetch(baseUrl + "/api/v1/auth/login", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ username, password })
          });

          const body = await readBody(response);

          if (!response.ok) {
            setOutput(body.text || "Login failed.", true);
            return;
          }

          if (!body.json || !body.json.accessToken) {
            setOutput("Login response missing accessToken.", true);
            return;
          }

          setToken(body.json.accessToken);
          setOutput(body.text);
        } catch (err) {
          setOutput(String(err), true);
        }
      });

      healthBtn.addEventListener("click", handleHealth);
      wgStateBtn.addEventListener("click", function () {
        callAuthorized("/api/v1/admin/wg/state");
      });
      reconcileBtn.addEventListener("click", function () {
        callAuthorized("/api/v1/admin/wg/reconcile?mode=dry-run");
      });
      logoutBtn.addEventListener("click", function () {
        setToken("");
        setOutput("Logged out. Session storage cleared.");
        setPeerError("");
        clearPeerResult();
        setPeerStatus("Login required", false);
      });
      peerForm.addEventListener("submit", handleCreatePeer);
      peerCopyBtn.addEventListener("click", copyPeerConfig);
      peerClearBtn.addEventListener("click", function () {
        peerForm.reset();
        clearPeerResult();
        setPeerError("");
        setPeerStatus(getToken() ? "Ready" : "Login required", Boolean(getToken()));
      });

      updateStatus();
    })();
  </script>
</body>
</html>
""";

[AcceptVerbs("GET", "HEAD")]
[Route("/admin")]
    public ContentResult Index()
    {
        // Set security headers
        Response.Headers["Cache-Control"] = "no-store, no-cache";
        Response.Headers["Pragma"] = "no-cache";
        Response.Headers["X-Content-Type-Options"] = "nosniff";
        Response.Headers["X-Frame-Options"] = "DENY";
        Response.Headers["Referrer-Policy"] = "no-referrer";
        Response.Headers["Content-Security-Policy"] = 
            "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; connect-src 'self'";

        return Content(AdminHtml, "text/html; charset=utf-8");
    }
}
