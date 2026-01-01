namespace VpnService.Infrastructure.Interfaces;

public interface ITokenService
{
    (string accessToken, int expiresIn) GenerateAccessToken(Guid userId);
    string GenerateRefreshToken();
    string HashToken(string token);
    bool VerifyRefreshToken(string token, string hash);
}
