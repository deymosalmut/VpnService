using Microsoft.EntityFrameworkCore;
using VpnService.Domain.Entities;

namespace VpnService.Infrastructure.Persistence;

public class VpnDbContext : DbContext
{
    public DbSet<VpnServer> VpnServers { get; set; }
    public DbSet<VpnPeer> VpnPeers { get; set; }
    public DbSet<RefreshToken> RefreshTokens { get; set; }

    public VpnDbContext(DbContextOptions<VpnDbContext> options) : base(options)
    {
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.ApplyConfigurationsFromAssembly(typeof(VpnDbContext).Assembly);
    }
}
