using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using VpnService.Domain.Entities;

namespace VpnService.Infrastructure.Persistence.Configurations;

public class VpnServerConfiguration : IEntityTypeConfiguration<VpnServer>
{
    public void Configure(EntityTypeBuilder<VpnServer> builder)
    {
        builder.HasKey(s => s.Id);

        builder.Property(s => s.Name)
            .IsRequired()
            .HasMaxLength(255);

        builder.Property(s => s.Gateway)
            .IsRequired()
            .HasMaxLength(50);

        builder.Property(s => s.Network)
            .IsRequired()
            .HasMaxLength(50);

        builder.Property(s => s.CreatedAt)
            .HasDefaultValueSql("CURRENT_TIMESTAMP");

        builder.HasIndex(s => s.Name).IsUnique();

        builder.HasMany(s => s.Peers)
            .WithOne(p => p.VpnServer)
            .HasForeignKey(p => p.VpnServerId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
