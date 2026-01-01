namespace VpnService.Application.UseCases;

public class GetPeerConfigCommand
{
    public Guid PeerId { get; set; }
}

public class GetPeerConfigHandler
{
    private readonly Infrastructure.Repositories.IPeerRepository _peerRepository;

    public GetPeerConfigHandler(Infrastructure.Repositories.IPeerRepository peerRepository)
    {
        _peerRepository = peerRepository;
    }

    public async Task<DTOs.PeerResponse> HandleAsync(GetPeerConfigCommand command)
    {
        var peer = await _peerRepository.GetByIdAsync(command.PeerId);
        if (peer == null)
            throw new InvalidOperationException("Peer not found");

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
