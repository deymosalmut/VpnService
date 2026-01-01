using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using VpnService.Domain.Entities;

namespace VpnService.Infrastructure.Persistence.Configurations;

public class RefreshTokenConfiguration : IEntityTypeConfiguration<RefreshToken>
{
    public void Configure(EntityTypeBuilder<RefreshToken> builder)
    {
        builder.HasKey(t => t.Id);

        builder.Property(t => t.TokenHash)
            .IsRequired()
            .HasMaxLength(512);

        builder.Property(t => t.DeviceId)
            .IsRequired()
            .HasMaxLength(255);

        builder.Property(t => t.CreatedAt)
            .HasDefaultValueSql("CURRENT_TIMESTAMP");

        builder.Property(t => t.IsRevoked)
            .HasDefaultValue(false);

        builder.HasIndex(t => t.TokenHash).IsUnique();
        builder.HasIndex(t => t.DeviceId);
    }
}
