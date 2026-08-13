namespace Aumbrye.Shared.Contracts.Auth;

public sealed record RegisterRequest(string Email, string Password);

public sealed record LoginRequest(string Email, string Password);

/// <summary>
/// Refresh request. <see cref="RefreshToken"/> is optional: browser clients using cookie transport
/// send nothing and the server reads the httpOnly cookie instead.
/// </summary>
public sealed record RefreshRequest(string? RefreshToken = null);

public sealed record LogoutRequest(string? RefreshToken = null);

public sealed record SteamAuthRequest(string TicketHex, uint AppId);

public sealed record LinkSteamRequest(string TicketHex, uint AppId);

/// <summary>
/// Issued tokens. <see cref="RefreshToken"/> is null when the client opted into cookie transport
/// (see <see cref="AuthTransport"/>) — the refresh token then lives only in an httpOnly cookie and
/// is never exposed to page scripts.
/// </summary>
public sealed record AuthTokensResponse(
    string AccessToken,
    string? RefreshToken,
    DateTimeOffset AccessTokenExpiresAt);

/// <summary>
/// Negotiates where the refresh token lives.
/// </summary>
/// <remarks>
/// The Godot client keeps using body tokens (it has no cookie jar and persists its own encrypted
/// session file). Browsers opt into cookie transport by sending the header, which keeps both
/// clients on one set of endpoints instead of forking the auth surface.
/// </remarks>
public static class AuthTransport
{
    /// <summary>Request header a client sends to ask for cookie transport.</summary>
    public const string HeaderName = "X-Auth-Transport";

    /// <summary>Header value selecting cookie transport.</summary>
    public const string Cookie = "cookie";

    /// <summary>Name of the httpOnly refresh-token cookie.</summary>
    public const string CookieName = "aumbrye_rt";

    /// <summary>Path the cookie is scoped to, so it is never sent to non-auth endpoints.</summary>
    public const string CookiePath = "/api/v1/auth";
}

public sealed record AuthUserResponse(Guid Id, string Email);

public sealed record AuthResponse(AuthTokensResponse Tokens, AuthUserResponse User);
