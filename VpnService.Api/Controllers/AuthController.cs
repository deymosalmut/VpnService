using Microsoft.AspNetCore.Mvc;
using System.Security.Cryptography;
using System.Text;
using VpnService.Application.DTOs;
using VpnService.Infrastructure.Interfaces;
using VpnService.Infrastructure.Repositories;

namespace VpnService.Api.Controllers;

[ApiController]
[Route("api/v1/[controller]")]
public class AuthController : ControllerBase
{
    private readonly ITokenService _tokenService;
    private readonly IRefreshTokenRepository _refreshTokenRepository;
    private readonly ILogger<AuthController> _logger;

    private readonly string _adminUser;
    private readonly string _adminPass;
    private readonly Guid _adminUserId;

    public AuthController(
        ITokenService tokenService,
        IRefreshTokenRepository refreshTokenRepository,
        ILogger<AuthController> logger,
        IConfiguration config)
    {
        _tokenService = tokenService;
        _refreshTokenRepository = refreshTokenRepository;
        _logger = logger;

        _adminUser = (config["AdminAuth:Username"] ?? "admin").Trim();
        _adminPass = (config["AdminAuth:Password"] ?? string.Empty);

        // Если явно задан UserId — используем его, иначе детерминируем из username
        if (!Guid.TryParse(config["AdminAuth:UserId"], out _adminUserId))
            _adminUserId = StableGuidFromString(_adminUser);
    }

    [HttpPost("login")]
    [ProducesResponseType(typeof(AuthLoginResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<AuthLoginResponse>> Login([FromBody] AuthLoginRequest request)
    {
        // Fail-closed: если пароль не задан в конфиге/env — логин всегда запрещён
        if (string.IsNullOrWhiteSpace(_adminPass))
        {
            _logger.LogError("AdminAuth:Password is not configured; refusing all login attempts.");
            return Unauthorized("Invalid credentials");
        }

        if (request == null || string.IsNullOrWhiteSpace(request.Username) || string.IsNullOrWhiteSpace(request.Password))
            return Unauthorized("Invalid credentials");

        if (!IsValidAdminCredentials(request.Username, request.Password))
        {
            _logger.LogWarning("Failed login attempt for user: {Username}", request.Username);
            return Unauthorized("Invalid credentials");
        }

        var (accessToken, expiresIn) = _tokenService.GenerateAccessToken(_adminUserId);
        var refreshToken = _tokenService.GenerateRefreshToken();
        var tokenHash = _tokenService.HashToken(refreshToken);

        var refreshTokenEntity = new Domain.Entities.RefreshToken
        {
            Id = Guid.NewGuid(),
            TokenHash = tokenHash,
            DeviceId = request.Username, // MVP: используем username как идентификатор (можно заменить на X-Device-Id позже)
            ExpiresAt = DateTime.UtcNow.AddDays(7),
            CreatedAt = DateTime.UtcNow,
            IsRevoked = false
        };

        await _refreshTokenRepository.AddAsync(refreshTokenEntity);
        await _refreshTokenRepository.SaveChangesAsync();

        _logger.LogInformation("User logged in: {Username}", request.Username);

        return Ok(new AuthLoginResponse
        {
            AccessToken = accessToken,
            RefreshToken = refreshToken,
            ExpiresIn = expiresIn
        });
    }

    [HttpPost("refresh")]
    [ProducesResponseType(typeof(AuthLoginResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<AuthLoginResponse>> Refresh([FromBody] AuthRefreshRequest request)
    {
        if (request == null || string.IsNullOrWhiteSpace(request.RefreshToken))
            return Unauthorized("Refresh token is required");

        var tokenHash = _tokenService.HashToken(request.RefreshToken);
        var storedToken = await _refreshTokenRepository.GetByHashAsync(tokenHash);

        // ВАЖНО: учитываем IsRevoked
        if (storedToken == null || storedToken.IsRevoked || storedToken.ExpiresAt < DateTime.UtcNow)
        {
            _logger.LogWarning("Invalid/expired/revoked refresh token");
            return Unauthorized("Invalid or expired refresh token");
        }

        var (accessToken, expiresIn) = _tokenService.GenerateAccessToken(_adminUserId);
        var newRefreshToken = _tokenService.GenerateRefreshToken();
        var newTokenHash = _tokenService.HashToken(newRefreshToken);

        // revoke old (single-use)
        storedToken.IsRevoked = true;
        await _refreshTokenRepository.UpdateAsync(storedToken);

        var newRefreshTokenEntity = new Domain.Entities.RefreshToken
        {
            Id = Guid.NewGuid(),
            TokenHash = newTokenHash,
            DeviceId = storedToken.DeviceId,
            ExpiresAt = DateTime.UtcNow.AddDays(7),
            CreatedAt = DateTime.UtcNow,
            IsRevoked = false
        };

        await _refreshTokenRepository.AddAsync(newRefreshTokenEntity);
        await _refreshTokenRepository.SaveChangesAsync();

        _logger.LogInformation("Token refreshed for device: {DeviceId}", storedToken.DeviceId);

        return Ok(new AuthLoginResponse
        {
            AccessToken = accessToken,
            RefreshToken = newRefreshToken,
            ExpiresIn = expiresIn
        });
    }

    [HttpPost("logout")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<ActionResult> Logout([FromBody] AuthRefreshRequest request)
    {
        if (request == null || string.IsNullOrWhiteSpace(request.RefreshToken))
            return BadRequest("Refresh token is required");

        var tokenHash = _tokenService.HashToken(request.RefreshToken);
        var storedToken = await _refreshTokenRepository.GetByHashAsync(tokenHash);

        if (storedToken != null && !storedToken.IsRevoked)
        {
            storedToken.IsRevoked = true;
            await _refreshTokenRepository.UpdateAsync(storedToken);
            await _refreshTokenRepository.SaveChangesAsync();
            _logger.LogInformation("User logged out: {DeviceId}", storedToken.DeviceId);
        }

        return Ok();
    }

    private bool IsValidAdminCredentials(string username, string password)
    {
        // username обычным сравнение (можно сделать fixed-time тоже, но это не критично)
        if (!string.Equals(username.Trim(), _adminUser, StringComparison.Ordinal))
            return false;

        // fixed-time compare для пароля
        var a = Encoding.UTF8.GetBytes(password);
        var b = Encoding.UTF8.GetBytes(_adminPass);

        // FixedTimeEquals требует одинаковую длину; приводим к одинаковой длине без раннего выхода
        var max = Math.Max(a.Length, b.Length);
        var aa = new byte[max];
        var bb = new byte[max];
        Buffer.BlockCopy(a, 0, aa, 0, a.Length);
        Buffer.BlockCopy(b, 0, bb, 0, b.Length);

        return CryptographicOperations.FixedTimeEquals(aa, bb);
    }

    private static Guid StableGuidFromString(string input)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(input));
        // первые 16 байт -> GUID
        var guidBytes = new byte[16];
        Buffer.BlockCopy(bytes, 0, guidBytes, 0, 16);
        return new Guid(guidBytes);
    }
}
