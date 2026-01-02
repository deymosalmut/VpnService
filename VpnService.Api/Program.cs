using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Serilog;
using System.Text;
using VpnService.Infrastructure.Interfaces;
using VpnService.Infrastructure.Auth;
using VpnService.Infrastructure.Persistence;
using VpnService.Infrastructure.Repositories;
using VpnService.Infrastructure.Abstractions;
using VpnService.Infrastructure.WireGuard;

var builder = WebApplication.CreateBuilder(args);

// Serilog configuration
Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Information()
    .WriteTo.Console()
    .WriteTo.File("logs/vpnservice-.txt", rollingInterval: RollingInterval.Day)
    .CreateLogger();

builder.Host.UseSerilog();

// Add services
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddHealthChecks();

// Database configuration
var connectionString = builder.Configuration.GetConnectionString("DefaultConnection");

if (string.IsNullOrEmpty(connectionString) || connectionString.Contains("localhost"))
{
    // Use in-memory database for development/testing
    builder.Services.AddDbContext<VpnDbContext>(options =>
        options.UseInMemoryDatabase("VpnServiceDb"));
}
else
{
    // Use PostgreSQL for production
    builder.Services.AddDbContext<VpnDbContext>(options =>
        options.UseNpgsql(connectionString));
}

// Repository registration
builder.Services.AddScoped<IPeerRepository, PeerRepository>();
builder.Services.AddScoped<IRefreshTokenRepository, RefreshTokenRepository>();

// WireGuard state reader (read-only adapter)
builder.Services.AddScoped<IWireGuardStateReader, LinuxWireGuardStateReader>();

// WireGuard command writer (write operations)
builder.Services.AddScoped<IWireGuardCommandWriter, LinuxWireGuardCommandWriter>();

// Token service registration
var jwtKey = builder.Configuration["Jwt:Key"] ?? "your-secret-key-that-is-at-least-32-characters-long!";
var jwtIssuer = builder.Configuration["Jwt:Issuer"] ?? "VpnService";

builder.Services.AddSingleton<ITokenService>(new TokenService(jwtKey, jwtIssuer));

// JWT Authentication configuration
builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = jwtIssuer,
            ValidAudience = "vpn-api",
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtKey))
        };
    });

builder.Services.AddAuthorization();

// Logging
var app = builder.Build();

// Configure the HTTP request pipeline
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.MapHealthChecks("/health");

// Database migration (only for SQL databases)
if (!app.Environment.IsDevelopment() || 
    (builder.Configuration.GetConnectionString("DefaultConnection") != null && 
     !builder.Configuration.GetConnectionString("DefaultConnection")!.Contains("localhost")))
{
    using (var scope = app.Services.CreateScope())
    {
        var dbContext = scope.ServiceProvider.GetRequiredService<VpnDbContext>();
        try
        {
            dbContext.Database.Migrate();
            Log.Information("Database migration completed successfully");
        }
        catch (Exception ex)
        {
            Log.Error(ex, "Error during database migration");
        }
    }
}
else
{
    // Create tables for In-Memory database
    using (var scope = app.Services.CreateScope())
    {
        var dbContext = scope.ServiceProvider.GetRequiredService<VpnDbContext>();
        dbContext.Database.EnsureCreated();
        Log.Information("In-memory database created successfully");
    }
}

Log.Information("VPN Service starting...");
app.Run();
