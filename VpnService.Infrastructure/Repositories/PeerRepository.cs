using Microsoft.EntityFrameworkCore;
using VpnService.Domain.Entities;
using VpnService.Infrastructure.Persistence;

namespace VpnService.Infrastructure.Repositories;

public class PeerRepository : IPeerRepository
{
    private readonly VpnDbContext _context;

    public PeerRepository(VpnDbContext context)
    {
        _context = context;
    }

    public async Task<VpnPeer?> GetByIdAsync(Guid id)
    {
        return await _context.VpnPeers
            .AsNoTracking()
            .FirstOrDefaultAsync(p => p.Id == id);
    }

    public async Task<VpnPeer?> GetByPublicKeyAsync(string publicKey)
    {
        return await _context.VpnPeers
            .AsNoTracking()
            .FirstOrDefaultAsync(p => p.PublicKey == publicKey);
    }

    public async Task<VpnPeer?> GetByIpAsync(string ip)
    {
        return await _context.VpnPeers
            .AsNoTracking()
            .FirstOrDefaultAsync(p => p.AssignedIp == ip);
    }

    public async Task<IEnumerable<VpnPeer>> GetAllAsync()
    {
        return await _context.VpnPeers
            .AsNoTracking()
            .ToListAsync();
    }

    public async Task<IEnumerable<VpnPeer>> GetByServerIdAsync(Guid serverId)
    {
        return await _context.VpnPeers
            .AsNoTracking()
            .Where(p => p.VpnServerId == serverId)
            .ToListAsync();
    }

    public async Task AddAsync(VpnPeer peer)
    {
        await _context.VpnPeers.AddAsync(peer);
    }

    public Task UpdateAsync(VpnPeer peer)
    {
        peer.UpdatedAt = DateTime.UtcNow;
        _context.VpnPeers.Update(peer);
        return Task.CompletedTask;
    }

    public async Task DeleteAsync(Guid id)
    {
        var peer = await _context.VpnPeers.FindAsync(id);
        if (peer != null)
        {
            _context.VpnPeers.Remove(peer);
        }
    }

    public async Task SaveChangesAsync()
    {
        await _context.SaveChangesAsync();
    }
}
