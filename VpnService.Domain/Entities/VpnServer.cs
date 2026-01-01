namespace VpnService.Domain.Entities;

public class VpnServer
{
    public Guid Id { get; set; }
    
    public string Name { get; set; } = null!;
    
    public string Gateway { get; set; } = null!;
    
    public string Network { get; set; } = null!;
    
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    
    public ICollection<VpnPeer> Peers { get; set; } = new List<VpnPeer>();
}
