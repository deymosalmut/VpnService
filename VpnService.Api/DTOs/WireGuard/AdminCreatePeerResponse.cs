namespace VpnService.Api.DTOs.WireGuard;

public sealed class AdminCreatePeerResponse
{
    public string Iface { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Address { get; set; } = string.Empty;
    public string PublicKey { get; set; } = string.Empty;
    public string Config { get; set; } = string.Empty;
    public string QrPngBase64 { get; set; } = string.Empty;
    public string QrDataUrl { get; set; } = string.Empty;
}
