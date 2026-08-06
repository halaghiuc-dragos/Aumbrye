using System.Security.Cryptography;
using Aumbrye.Application.Abstractions;
using Microsoft.Extensions.Configuration;
using Aumbrye.Infrastructure.Security;

namespace Aumbrye.Infrastructure.Security;

public class BcryptPasswordHasher : IPasswordHasher
{
    public string Hash(string password) => BCrypt.Net.BCrypt.HashPassword(password, workFactor: 11);

    public bool Verify(string password, string hash) => BCrypt.Net.BCrypt.Verify(password, hash);
}

public class JwtTokenService : ITokenService
{
    private readonly string _issuer;
    private readonly string _audience;
    private readonly byte[] _key;
    private readonly TimeSpan _accessLifetime;

    public JwtTokenService(Microsoft.Extensions.Configuration.IConfiguration configuration)
    {
        _issuer = configuration["Jwt:Issuer"] ?? "aumbrye";
        _audience = configuration["Jwt:Audience"] ?? "aumbrye-client";
        var useInMemory = configuration.GetValue<bool>("UseInMemoryStores")
                          || string.Equals(
                              configuration["ASPNETCORE_ENVIRONMENT"],
                              "Testing",
                              StringComparison.OrdinalIgnoreCase);
        _key = JwtSigningKey.FromConfiguration(configuration, useInMemory);
        _accessLifetime = TimeSpan.FromMinutes(
            int.TryParse(configuration["Jwt:AccessTokenMinutes"], out var m) ? m : 15);
    }

    public string CreateAccessToken(Domain.Entities.Account account, out DateTimeOffset expiresAt)
    {
        expiresAt = DateTimeOffset.UtcNow.Add(_accessLifetime);
        var handler = new System.IdentityModel.Tokens.Jwt.JwtSecurityTokenHandler();
        var claims = new List<System.Security.Claims.Claim>
        {
            new(System.Security.Claims.ClaimTypes.NameIdentifier, account.Id.ToString()),
        };
        if (!string.IsNullOrEmpty(account.Email))
            claims.Add(new System.Security.Claims.Claim(System.Security.Claims.ClaimTypes.Email, account.Email));
        var descriptor = new Microsoft.IdentityModel.Tokens.SecurityTokenDescriptor
        {
            Subject = new System.Security.Claims.ClaimsIdentity(claims),
            Expires = expiresAt.UtcDateTime,
            Issuer = _issuer,
            Audience = _audience,
            SigningCredentials = new Microsoft.IdentityModel.Tokens.SigningCredentials(
                new Microsoft.IdentityModel.Tokens.SymmetricSecurityKey(_key),
                Microsoft.IdentityModel.Tokens.SecurityAlgorithms.HmacSha256),
        };
        return handler.WriteToken(handler.CreateToken(descriptor));
    }

    public string CreateRefreshToken() => Convert.ToBase64String(RandomNumberGenerator.GetBytes(64));

    public string HashToken(string token)
    {
        var bytes = SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(token));
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }

    public Guid? GetAccountIdFromAccessToken(string accessToken)
    {
        try
        {
            var handler = new System.IdentityModel.Tokens.Jwt.JwtSecurityTokenHandler();
            var parameters = new Microsoft.IdentityModel.Tokens.TokenValidationParameters
            {
                ValidateIssuer = true,
                ValidateAudience = true,
                ValidateLifetime = true,
                ValidateIssuerSigningKey = true,
                ValidIssuer = _issuer,
                ValidAudience = _audience,
                IssuerSigningKey = new Microsoft.IdentityModel.Tokens.SymmetricSecurityKey(_key),
            };
            var principal = handler.ValidateToken(accessToken, parameters, out _);
            var id = principal.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
            return Guid.TryParse(id, out var guid) ? guid : null;
        }
        catch
        {
            return null;
        }
    }
}
