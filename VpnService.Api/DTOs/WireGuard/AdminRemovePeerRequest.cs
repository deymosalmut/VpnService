namespace VpnService.Api.DTOs.WireGuard;

public sealed class AdminRemovePeerRequest
{
    public string Interface { get; set; } = "wg1";
    public string PublicKey { get; set; } = default!;
}
