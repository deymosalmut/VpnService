namespace VpnService.Api.DTOs.WireGuard;

public sealed class AdminAddPeerRequest
{
    public string Interface { get; set; } = "wg1";
    public string PublicKey { get; set; } = default!;
    public string AllowedIpCidr { get; set; } = default!; // "10.0.0.2/32"
}
