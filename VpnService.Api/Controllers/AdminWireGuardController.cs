using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using VpnService.Application.Interfaces;
using VpnService.Infrastructure.Abstractions.WireGuard;
using VpnService.Api.DTOs.WireGuard;

namespace VpnService.Api.Controllers;

[ApiController]
[Route("api/v1/admin/wg")]
[Authorize] // MVP: достаточно Authorize, роли добавим позже
public sealed class AdminWireGuardController : ControllerBase
{
    private readonly IWireGuardStateReader _reader; // read-only for Stage 3

    public AdminWireGuardController(IWireGuardStateReader reader)
    {
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
    public IActionResult AddPeer() => StatusCode(501, new { status = "NotImplemented", message = "Write operations disabled in Stage 3" });

    // 3.2 — remove peer (not implemented in read-only Stage 3)
    [HttpPost("peer/remove")]
    public IActionResult RemovePeer() => StatusCode(501, new { status = "NotImplemented", message = "Write operations disabled in Stage 3" });
}
