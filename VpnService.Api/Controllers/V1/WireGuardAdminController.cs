using System.Threading;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using VpnService.Infrastructure.Abstractions.WireGuard;

namespace VpnService.Api.Controllers.V1
{
    [ApiController]
    [Route("api/v1/admin/wg")]
    [Authorize]
    public class WireGuardAdminController : ControllerBase
    {
        private readonly IWireGuardStateReader _reader;

        public WireGuardAdminController(IWireGuardStateReader reader)
        {
            _reader = reader;
        }

        [HttpGet("state")]
        public async Task<IActionResult> GetState([FromQuery] string iface = "wg1", CancellationToken ct = default)
        {
            var json = await _reader.ReadStateJsonAsync(iface, ct);
            return Content(json, "application/json");
        }

        [HttpGet("reconcile")]
        public IActionResult Reconcile([FromQuery] string iface = "wg1", [FromQuery] string mode = "dry-run")
        {
            return Ok(new
            {
                iface,
                summary = new { missing = 0, orphan = 0, drift = 0 },
                details = new object[0]
            });
        }
    }
}
