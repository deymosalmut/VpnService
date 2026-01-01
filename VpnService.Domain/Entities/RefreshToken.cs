namespace VpnService.Domain.Entities;

public class RefreshToken
{
    public Guid Id { get; set; }
    
    public string TokenHash { get; set; } = null!;
    
    public string DeviceId { get; set; } = null!;
    
    public DateTime ExpiresAt { get; set; }
    
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    
    public bool IsRevoked { get; set; } = false;
}
