namespace VpnService.Api.DTOs.WireGuard;

public sealed class AdminCreatePeerRequest
{
    public string? Iface { get; set; }
    public string Name { get; set; } = string.Empty;
    public string[]? AllowedIps { get; set; }
    public string? Dns { get; set; }
    public string? EndpointHost { get; set; }
    public int? EndpointPort { get; set; }
}
