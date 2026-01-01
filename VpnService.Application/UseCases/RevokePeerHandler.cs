namespace VpnService.Application.UseCases;

public class RevokePeerCommand
{
    public Guid PeerId { get; set; }
}

public class RevokePeerHandler
{
    private readonly Infrastructure.Repositories.IPeerRepository _peerRepository;

    public RevokePeerHandler(Infrastructure.Repositories.IPeerRepository peerRepository)
    {
        _peerRepository = peerRepository;
    }

    public async Task<DTOs.PeerResponse> HandleAsync(RevokePeerCommand command)
    {
        var peer = await _peerRepository.GetByIdAsync(command.PeerId);
        if (peer == null)
            throw new InvalidOperationException("Peer not found");

        peer.Status = Domain.Enums.PeerStatus.Revoked;
        peer.UpdatedAt = DateTime.UtcNow;

        await _peerRepository.UpdateAsync(peer);
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
