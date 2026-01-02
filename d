B) Код в проект (добавь файлы)
1) DTO запросов (Api слой)
VpnService.Api/DTOs/WireGuard/AdminAddPeerRequest.cs
namespace VpnService.Api.DTOs.WireGuard;

public sealed class AdminAddPeerRequest
{
    public string Interface { get; set; } = "wg1";
    public string PublicKey { get; set; } = default!;
    public string AllowedIpCidr { get; set; } = default!; // "10.0.0.2/32"
}

VpnService.Api/DTOs/WireGuard/AdminRemovePeerRequest.cs
namespace VpnService.Api.DTOs.WireGuard;

public sealed class AdminRemovePeerRequest
{
    public string Interface { get; set; } = "wg1";
    public string PublicKey { get; set; } = default!;
}

2) Интерфейс write-операций (Application)
VpnService.Application/Interfaces/IWireGuardCommandWriter.cs
namespace VpnService.Application.Interfaces;

public interface IWireGuardCommandWriter
{
    Task AddPeerAsync(string iface, string publicKey, string allowedIpCidr, CancellationToken ct);
    Task RemovePeerAsync(string iface, string publicKey, CancellationToken ct);
}

3) Реализация через Linux Adapter (Infrastructure)
VpnService.Infrastructure/WireGuard/LinuxWireGuardCommandWriter.cs
using System.Diagnostics;
using System.Text;
using Microsoft.Extensions.Logging;
using VpnService.Application.Interfaces;

namespace VpnService.Infrastructure.WireGuard;

public sealed class LinuxWireGuardCommandWriter : IWireGuardCommandWriter
{
    private readonly ILogger<LinuxWireGuardCommandWriter> _logger;
    private readonly string _writeScriptPath;

    public LinuxWireGuardCommandWriter(ILogger<LinuxWireGuardCommandWriter> logger)
    {
        _logger = logger;
        _writeScriptPath = Environment.GetEnvironmentVariable("WG_WRITE_SCRIPT")
            ?? "/opt/vpn-adapter/wg_write.sh";
    }

    public async Task AddPeerAsync(string iface, string publicKey, string allowedIpCidr, CancellationToken ct)
    {
        ValidateIface(iface);
        ValidateWgPublicKey(publicKey);
        ValidateAllowedIpCidr(allowedIpCidr);

        var args = $"add {EscapeArg(iface)} {EscapeArg(publicKey)} {EscapeArg(allowedIpCidr)}";
        await RunScriptAsync(args, ct);
        _logger.LogInformation("WG peer added iface={Iface} allowed={Allowed}", iface, allowedIpCidr);
    }

    public async Task RemovePeerAsync(string iface, string publicKey, CancellationToken ct)
    {
        ValidateIface(iface);
        ValidateWgPublicKey(publicKey);

        var args = $"remove {EscapeArg(iface)} {EscapeArg(publicKey)}";
        await RunScriptAsync(args, ct);
        _logger.LogInformation("WG peer removed iface={Iface}", iface);
    }

    private async Task RunScriptAsync(string args, CancellationToken ct)
    {
        if (!File.Exists(_writeScriptPath))
            throw new InvalidOperationException($"WG write script not found: {_writeScriptPath}");

        using var p = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = "/usr/bin/env",
                Arguments = $"bash {_writeScriptPath} {args}",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            }
        };

        p.Start();

        var stdout = await p.StandardOutput.ReadToEndAsync(ct);
        var stderr = await p.StandardError.ReadToEndAsync(ct);
        await p.WaitForExitAsync(ct);

        if (p.ExitCode != 0)
        {
            var msg = $"WG write failed (exit {p.ExitCode}). stderr={stderr}";
            _logger.LogError("{Msg}", msg);
            throw new InvalidOperationException(msg);
        }
    }

    private static void ValidateIface(string iface)
    {
        // минимально безопасно: буквы/цифры/подчёрк/дефис
        if (string.IsNullOrWhiteSpace(iface) || iface.Length > 32 || iface.Any(ch => !(char.IsLetterOrDigit(ch) || ch is '_' or '-')))
            throw new ArgumentException("Invalid interface name");
    }

    private static void ValidateWgPublicKey(string key)
    {
        // WG pubkey = base64, обычно 44 символа с '=' на конце.
        if (string.IsNullOrWhiteSpace(key) || key.Length < 40 || key.Length > 60)
            throw new ArgumentException("Invalid WireGuard public key length");
        // можно усилить regex, но MVP достаточно
    }

    private static void ValidateAllowedIpCidr(string cidr)
    {
        // MVP: строго ожидаем /32
        if (string.IsNullOrWhiteSpace(cidr) || !cidr.EndsWith("/32"))
            throw new ArgumentException("AllowedIpCidr must be /32 in MVP");
    }

    private static string EscapeArg(string s)
    {
        // bash-аргумент через одинарные кавычки
        return "'" + s.Replace("'", "'\"'\"'") + "'";
    }
}

4) Admin Controller (Api слой)
VpnService.Api/Controllers/AdminWireGuardController.cs

(Если у тебя уже есть controller для GET /api/v1/admin/wg/state, просто добавь методы; если нет — создай целиком.)

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using VpnService.Application.Interfaces;
using VpnService.Api.DTOs.WireGuard;

namespace VpnService.Api.Controllers;

[ApiController]
[Route("api/v1/admin/wg")]
[Authorize] // MVP: достаточно Authorize, роли добавим позже
public sealed class AdminWireGuardController : ControllerBase
{
    private readonly IWireGuardCommandWriter _writer;
    private readonly IWireGuardStateReader _reader; // уже есть у тебя для state endpoint

    public AdminWireGuardController(IWireGuardCommandWriter writer, IWireGuardStateReader reader)
    {
        _writer = writer;
        _reader = reader;
    }

    // 3.1 (у тебя уже работает) — оставляем
    [HttpGet("state")]
    public async Task<IActionResult> GetState([FromQuery] string iface = "wg1", CancellationToken ct = default)
    {
        var json = await _reader.ReadStateJsonAsync(iface, ct);
        return Content(json, "application/json");
    }

    // 3.2 — add peer
    [HttpPost("peer/add")]
    public async Task<IActionResult> AddPeer([FromBody] AdminAddPeerRequest request, CancellationToken ct)
    {
        await _writer.AddPeerAsync(request.Interface, request.PublicKey, request.AllowedIpCidr, ct);
        return Ok(new { status = "OK" });
    }

    // 3.2 — remove peer
    [HttpPost("peer/remove")]
    public async Task<IActionResult> RemovePeer([FromBody] AdminRemovePeerRequest request, CancellationToken ct)
    {
        await _writer.RemovePeerAsync(request.Interface, request.PublicKey, ct);
        return Ok(new { status = "OK" });
    }
}


Важно: тут используется IWireGuardStateReader и метод ReadStateJsonAsync. Если у тебя сигнатура другая — скажи, я подгоню. Но идея: state reader возвращает JSON, а writer вызывает wg_write.sh.

5) Регистрация DI (Api/Program.cs)

В Program.cs добавь:

using VpnService.Application.Interfaces;
using VpnService.Infrastructure.WireGuard;

builder.Services.AddScoped<IWireGuardCommandWriter, LinuxWireGuardCommandWriter>();


И проверь, что у тебя есть:

app.UseAuthentication();
app.UseAuthorization();


(Порядок: UseAuthentication до UseAuthorization.)

C) Скрипт теста add/remove peer (Ubuntu)

Добавь файл:

scripts/stage3/60_write_smoke_test.sh
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

ENV_FILE="$SCRIPT_DIR/00_env"
load_env "$ENV_FILE"

require_cmd curl
require_cmd jq

log "[1] Health"
curl -fsS "$API_URL/health" >/dev/null
echo "OK"

log "[2] Login"
LOGIN_JSON="$(jq -n --arg u "$ADMIN_USERNAME" --arg p "$ADMIN_PASSWORD" '{username:$u,password:$p}')"
LOGIN_RESP="$(curl -fsS -X POST "$API_URL/api/v1/auth/login" -H "Content-Type: application/json" -d "$LOGIN_JSON")"
TOKEN="$(echo "$LOGIN_RESP" | jq -r '.accessToken')"
[[ -n "$TOKEN" && "$TOKEN" != "null" ]] || die "Login failed: $LOGIN_RESP"

log "[3] Generate test peer keypair on server (for test only)"
TEST_PRIV="$(wg genkey)"
TEST_PUB="$(echo "$TEST_PRIV" | wg pubkey)"
TEST_ALLOWED="10.0.0.250/32"

log "Test pubkey: $TEST_PUB"
log "Allowed: $TEST_ALLOWED"

log "[4] Call add peer endpoint"
ADD_JSON="$(jq -n --arg i "$WG_IFACE" --arg k "$TEST_PUB" --arg a "$TEST_ALLOWED" '{interface:$i, publicKey:$k, allowedIpCidr:$a}')"
curl -fsS -X POST "$API_URL/api/v1/admin/wg/peer/add" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$ADD_JSON" | jq .

log "[5] Verify peer exists in wg dump"
bash "$WG_DUMP_SCRIPT" "$WG_IFACE" | jq -e --arg k "$TEST_PUB" '.peers[] | select(.publicKey==$k)' >/dev/null \
  || die "Peer not found in wg dump after add"

log "[6] Call remove peer endpoint"
REM_JSON="$(jq -n --arg i "$WG_IFACE" --arg k "$TEST_PUB" '{interface:$i, publicKey:$k}')"
curl -fsS -X POST "$API_URL/api/v1/admin/wg/peer/remove" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$REM_JSON" | jq .

log "[7] Verify peer removed"
if bash "$WG_DUMP_SCRIPT" "$WG_IFACE" | jq -e --arg k "$TEST_PUB" '.peers[] | select(.publicKey==$k)' >/dev/null; then
  die "Peer still present in wg dump after remove"
fi

log "DONE: write-path smoke test OK"