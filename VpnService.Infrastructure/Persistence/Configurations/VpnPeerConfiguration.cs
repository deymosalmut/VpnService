using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using VpnService.Domain.Entities;

namespace VpnService.Infrastructure.Persistence.Configurations;

public class VpnPeerConfiguration : IEntityTypeConfiguration<VpnPeer>
{
    public void Configure(EntityTypeBuilder<VpnPeer> builder)
    {
        builder.HasKey(p => p.Id);

        builder.Property(p => p.PublicKey)
            .IsRequired()
            .HasMaxLength(512);

        builder.Property(p => p.AssignedIp)
            .IsRequired()
            .HasMaxLength(50);

        builder.Property(p => p.Status)
            .HasConversion<int>();

        builder.Property(p => p.CreatedAt)
            .HasDefaultValueSql("CURRENT_TIMESTAMP");

        builder.HasIndex(p => p.PublicKey).IsUnique();
        builder.HasIndex(p => p.AssignedIp).IsUnique();

        builder.HasOne(p => p.VpnServer)
            .WithMany(s => s.Peers)
            .HasForeignKey(p => p.VpnServerId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
