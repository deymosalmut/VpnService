namespace VpnService.Application.UseCases;

public class ListPeersHandler
{
    private readonly Infrastructure.Repositories.IPeerRepository _peerRepository;

    public ListPeersHandler(Infrastructure.Repositories.IPeerRepository peerRepository)
    {
        _peerRepository = peerRepository;
    }

    public async Task<DTOs.ListPeersResponse> HandleAsync()
    {
        var peers = await _peerRepository.GetAllAsync();

        var peerResponses = peers.Select(p => new DTOs.PeerResponse
        {
            Id = p.Id,
            PublicKey = p.PublicKey,
            AssignedIp = p.AssignedIp,
            Status = (int)p.Status,
            CreatedAt = p.CreatedAt,
            UpdatedAt = p.UpdatedAt
        }).ToList();

        return new DTOs.ListPeersResponse
        {
            Peers = peerResponses
        };
    }
}
