namespace VpnService.Application.Interfaces;

public interface IWireGuardCommandWriter
{
    Task AddPeerAsync(string iface, string publicKey, string allowedIpCidr, CancellationToken ct);
    Task RemovePeerAsync(string iface, string publicKey, CancellationToken ct);
}
