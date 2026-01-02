using System.Threading;
using System.Threading.Tasks;

namespace VpnService.Application.Interfaces;

public interface IWireGuardStateReader
{
    Task<string> GetDumpJsonAsync(string iface, CancellationToken ct = default);
}
