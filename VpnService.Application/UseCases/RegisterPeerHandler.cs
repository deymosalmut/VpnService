namespace VpnService.Application.UseCases;

public class RegisterPeerCommand
{
    public string PublicKey { get; set; } = null!;
    public string AssignedIp { get; set; } = null!;
    public Guid VpnServerId { get; set; }
}

public class RegisterPeerHandler
{
    private readonly Infrastructure.Repositories.IPeerRepository _peerRepository;

    public RegisterPeerHandler(Infrastructure.Repositories.IPeerRepository peerRepository)
    {
        _peerRepository = peerRepository;
    }

    public async Task<DTOs.PeerResponse> HandleAsync(RegisterPeerCommand command)
    {
        var existingPeer = await _peerRepository.GetByPublicKeyAsync(command.PublicKey);
        if (existingPeer != null)
            throw new InvalidOperationException("Peer with this public key already exists");

        var existingIp = await _peerRepository.GetByIpAsync(command.AssignedIp);
        if (existingIp != null)
            throw new InvalidOperationException("IP address already assigned");

        var peer = new Domain.Entities.VpnPeer
        {
            Id = Guid.NewGuid(),
            PublicKey = command.PublicKey,
            AssignedIp = command.AssignedIp,
            VpnServerId = command.VpnServerId,
            Status = Domain.Enums.PeerStatus.Active,
            CreatedAt = DateTime.UtcNow
        };

        await _peerRepository.AddAsync(peer);
        await _peerRepository.SaveChangesAsync();

        return new DTOs.PeerResponse
        {
            Id = peer.Id,
            PublicKey = peer.PublicKey,
            AssignedIp = peer.AssignedIp,
            Status = (int)peer.Status,
            CreatedAt = peer.CreatedAt,
            UpdatedAt = peer.UpdatedAt
        };
    }
}
