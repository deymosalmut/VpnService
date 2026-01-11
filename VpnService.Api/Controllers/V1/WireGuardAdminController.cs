using System.Threading;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using VpnService.Infrastructure.Abstractions.WireGuard;

namespace VpnService.Api.Controllers.V1
{
    [ApiController]
    [Route("api/v1/admin/wg")]
    [Authorize]
    public class WireGuardAdminController : ControllerBase
    {
        private readonly IWireGuardStateReader _reader;
        private readonly ILogger<WireGuardAdminController> _logger;
        private readonly string _iface;

        public WireGuardAdminController(
            IWireGuardStateReader reader,
            ILogger<WireGuardAdminController> logger,
            IConfiguration config)
        {
            _reader = reader;
            _logger = logger;

            // Конфиг: WireGuard:Interface (env: WireGuard__Interface)
            _iface = (config["WireGuard:Interface"] ?? "wg1").Trim();
            if (string.IsNullOrWhiteSpace(_iface))
                _iface = "wg1";
        }

        // Read-only: iface берём ТОЛЬКО из конфигурации (query не используем)
        [HttpGet("state")]
        public async Task<IActionResult> GetState(CancellationToken ct = default)
        {
            try
            {
                var json = await _reader.ReadStateJsonAsync(_iface, ct);

                // На всякий случай: избегаем кэширования
                Response.Headers["Cache-Control"] = "no-store, no-cache";
                Response.Headers["Pragma"] = "no-cache";

                return Content(json, "application/json");
            }
            catch (WireGuardInterfaceNotFoundException ex)
            {
                _logger.LogWarning(ex, "WireGuard interface not found: {Iface}", _iface);
                return NotFound(new { message = ex.Message, iface = _iface });
            }
            catch (InvalidOperationException ex)
            {
                _logger.LogError(ex, "WireGuard state read failed for iface={Iface}", _iface);
                return StatusCode(500, new { message = ex.Message, iface = _iface });
            }
        }

        // Пока stub: тоже не принимаем iface из query
        [HttpGet("reconcile")]
        public IActionResult Reconcile([FromQuery] string mode = "dry-run")
        {
            if (mode != "dry-run")
                return BadRequest(new { message = "Only mode=dry-run is supported for now." });

            return Ok(new
            {
                iface = _iface,
                mode,
                summary = new { missing = 0, orphan = 0, drift = 0 },
                details = new object[0]
            });
        }
    }
}
