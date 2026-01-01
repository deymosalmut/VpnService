namespace VpnService.Application.DTOs;

public class AuthLoginRequest
{
    public string Username { get; set; } = null!;
    public string Password { get; set; } = null!;
}

public class AuthLoginResponse
{
    public string AccessToken { get; set; } = null!;
    public string RefreshToken { get; set; } = null!;
    public int ExpiresIn { get; set; }
}

public class AuthRefreshRequest
{
    public string RefreshToken { get; set; } = null!;
}
