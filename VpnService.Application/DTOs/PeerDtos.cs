namespace VpnService.Application.DTOs;

public class CreatePeerRequest
{
    public string PublicKey { get; set; } = null!;
    public string AssignedIp { get; set; } = null!;
    public Guid VpnServerId { get; set; }
}

public class PeerResponse
{
    public Guid Id { get; set; }
    public string PublicKey { get; set; } = null!;
    public string AssignedIp { get; set; } = null!;
    public int Status { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
}

public class ListPeersResponse
{
    public IEnumerable<PeerResponse> Peers { get; set; } = new List<PeerResponse>();
}
