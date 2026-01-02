using System.Threading;
using System.Threading.Tasks;

namespace VpnService.Infrastructure.Abstractions.WireGuard;

public interface IWireGuardStateReader
{
    /// <summary>
    /// Read-only: returns JSON produced by wg_dump.sh for the given interface
    /// </summary>
    Task<string> ReadStateJsonAsync(string iface, CancellationToken ct = default);
}
