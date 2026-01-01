namespace VpnService.Domain.Entities;

public class VpnPeer
{
    public Guid Id { get; set; }
    
    public string PublicKey { get; set; } = null!;
    
    public string AssignedIp { get; set; } = null!;
    
    public Enums.PeerStatus Status { get; set; } = Enums.PeerStatus.Active;
    
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    
    public DateTime? UpdatedAt { get; set; }
    
    public Guid VpnServerId { get; set; }
    
    public VpnServer VpnServer { get; set; } = null!;
}
