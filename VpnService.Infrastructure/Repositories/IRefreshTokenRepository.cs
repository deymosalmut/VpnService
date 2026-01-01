using VpnService.Domain.Entities;

namespace VpnService.Infrastructure.Repositories;

public interface IRefreshTokenRepository
{
    Task<RefreshToken?> GetByHashAsync(string tokenHash);
    Task<RefreshToken?> GetByIdAsync(Guid id);
    Task AddAsync(RefreshToken token);
    Task UpdateAsync(RefreshToken token);
    Task DeleteAsync(Guid id);
    Task SaveChangesAsync();
}
