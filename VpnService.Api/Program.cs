using Microsoft.EntityFrameworkCore;
using Serilog;
using VpnService.Infrastructure.Interfaces;
using VpnService.Infrastructure.Auth;
using VpnService.Infrastructure.Persistence;
using VpnService.Infrastructure.Repositories;

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
var connectionString = builder.Configuration.GetConnectionString("DefaultConnection")
    ?? "Server=localhost;Port=5432;Database=vpnservice;User Id=postgres;Password=postgres;";

builder.Services.AddDbContext<VpnDbContext>(options =>
    options.UseNpgsql(connectionString));

// Repository registration
builder.Services.AddScoped<IPeerRepository, PeerRepository>();
builder.Services.AddScoped<IRefreshTokenRepository, RefreshTokenRepository>();

// Token service registration
var jwtKey = builder.Configuration["Jwt:Key"] ?? "your-secret-key-that-is-at-least-32-characters-long!";
var jwtIssuer = builder.Configuration["Jwt:Issuer"] ?? "VpnService";

builder.Services.AddSingleton<ITokenService>(new TokenService(jwtKey, jwtIssuer));

// Logging
var app = builder.Build();

// Configure the HTTP request pipeline
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.UseAuthorization();
app.MapControllers();
app.MapHealthChecks("/health");

// Database migration
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

Log.Information("VPN Service starting...");
app.Run();
