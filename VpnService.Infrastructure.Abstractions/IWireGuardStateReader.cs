using System.Threading;
using System.Threading.Tasks;

namespace VpnService.Infrastructure.Abstractions;

public interface IWireGuardStateReader
{
    Task<string> GetDumpJsonAsync(string iface, CancellationToken ct = default);
}
