using System;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using VpnService.Infrastructure.Persistence;

namespace VpnService.Infrastructure.Persistence
{
    /// <summary>
    /// Design-time factory for EF Core tools (dotnet ef).
    /// Keeps migrations workable without relying on DI/host startup.
    /// </summary>
    public sealed class VpnDbContextFactory : IDesignTimeDbContextFactory<VpnDbContext>
    {
        public VpnDbContext CreateDbContext(string[] args)
        {
            var host = GetEnv("PG_HOST", "127.0.0.1");
            var port = GetEnv("PG_PORT", "5432");
            var db   = GetEnv("PG_DATABASE", GetEnv("PG_DB", "vpnservice"));
            var user = GetEnv("PG_USER", "vpnservice");
            var pass = GetEnv("PG_PASSWORD", "");

            if (string.IsNullOrWhiteSpace(pass))
                throw new InvalidOperationException("PG_PASSWORD is empty. Provide PG_PASSWORD for design-time migrations.");

            var conn = $"Host={host};Port={port};Database={db};Username={user};Password={pass};Include Error Detail=true";

            var options = new DbContextOptionsBuilder<VpnDbContext>()
                .UseNpgsql(conn)
                .Options;

            return new VpnDbContext(options);
        }

        private static string GetEnv(string key, string fallback)
            => Environment.GetEnvironmentVariable(key) is { Length: > 0 } v ? v : fallback;
    }
}
