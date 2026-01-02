// Obsolete duplicate. Use VpnService.Infrastructure.Abstractions.WireGuard.IWireGuardStateReader instead.
using System.Threading;
using System.Threading.Tasks;

namespace VpnService.Application.Interfaces.Obsolete;

public interface IWireGuardStateReader_Old
{
    Task<string> GetDumpJsonAsync(string iface, CancellationToken ct = default);
}
