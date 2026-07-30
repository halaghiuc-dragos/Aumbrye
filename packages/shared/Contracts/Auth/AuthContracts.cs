namespace Aumbrye.Shared.Contracts.Auth;

public sealed record RegisterRequest(string Email, string Password);

public sealed record LoginRequest(string Email, string Password);

public sealed record RefreshRequest(string RefreshToken);

public sealed record AuthTokensResponse(
    string AccessToken,
    string RefreshToken,
    DateTimeOffset AccessTokenExpiresAt);

public sealed record AuthUserResponse(Guid Id, string Email);

public sealed record AuthResponse(AuthTokensResponse Tokens, AuthUserResponse User);
