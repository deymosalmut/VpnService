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
