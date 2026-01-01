using System.IdentityModel.Tokens.Jwt;
using System.Security.Cryptography;
using System.Text;
using Microsoft.IdentityModel.Tokens;
using VpnService.Infrastructure.Interfaces;

namespace VpnService.Infrastructure.Auth;

public class TokenService : ITokenService
{
    private readonly string _jwtKey;
    private readonly string _jwtIssuer;
    private const int AccessTokenExpirationMinutes = 15;

    public TokenService(string jwtKey, string jwtIssuer)
    {
        if (string.IsNullOrWhiteSpace(jwtKey) || jwtKey.Length < 32)
            throw new ArgumentException("JWT key must be at least 32 characters");
        
        _jwtKey = jwtKey;
        _jwtIssuer = jwtIssuer;
    }

    public (string accessToken, int expiresIn) GenerateAccessToken(Guid userId)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_jwtKey));
        var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var claims = new List<System.Security.Claims.Claim>
        {
            new(System.Security.Claims.ClaimTypes.NameIdentifier, userId.ToString()),
        };

        var token = new JwtSecurityToken(
            issuer: _jwtIssuer,
            audience: "vpn-api",
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(AccessTokenExpirationMinutes),
            signingCredentials: credentials);

        var accessToken = new JwtSecurityTokenHandler().WriteToken(token);
        return (accessToken, AccessTokenExpirationMinutes * 60);
    }

    public string GenerateRefreshToken()
    {
        var randomNumber = new byte[32];
        using (var rng = RandomNumberGenerator.Create())
        {
            rng.GetBytes(randomNumber);
            return Convert.ToBase64String(randomNumber);
        }
    }

    public string HashToken(string token)
    {
        using (var sha256 = SHA256.Create())
        {
            var hashedBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(token));
            return Convert.ToBase64String(hashedBytes);
        }
    }

    public bool VerifyRefreshToken(string token, string hash)
    {
        var computedHash = HashToken(token);
        return computedHash == hash;
    }
}
