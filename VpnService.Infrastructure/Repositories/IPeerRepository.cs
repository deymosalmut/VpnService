using VpnService.Domain.Entities;

namespace VpnService.Infrastructure.Repositories;

public interface IPeerRepository
{
    Task<VpnPeer?> GetByIdAsync(Guid id);
    Task<VpnPeer?> GetByPublicKeyAsync(string publicKey);
    Task<VpnPeer?> GetByIpAsync(string ip);
    Task<IEnumerable<VpnPeer>> GetAllAsync();
    Task<IEnumerable<VpnPeer>> GetByServerIdAsync(Guid serverId);
    Task AddAsync(VpnPeer peer);
    Task UpdateAsync(VpnPeer peer);
    Task DeleteAsync(Guid id);
    Task SaveChangesAsync();
}
