using Aumbrye.Application.Abstractions;
using Aumbrye.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace Aumbrye.Application.Services;

public class AuthService : IAuthService
{
    private readonly DbContext _db;
    private readonly IPasswordHasher _passwordHasher;
    private readonly ITokenService _tokenService;

    public AuthService(DbContext db, IPasswordHasher passwordHasher, ITokenService tokenService)
    {
        _db = db;
        _passwordHasher = passwordHasher;
        _tokenService = tokenService;
    }

    public async Task<AuthResult> RegisterAsync(string email, string password, CancellationToken ct = default)
    {
        email = email.Trim().ToLowerInvariant();
        if (string.IsNullOrWhiteSpace(email) || !email.Contains('@') || email.Length > 256)
            return new AuthResult(false, Error: "Valid email required.");
        if (password.Length < 8 || password.Length > 128)
            return new AuthResult(false, Error: "Password must be 8–128 characters.");

        var exists = await _db.Set<Account>().AnyAsync(a => a.Email == email, ct);
        if (exists)
            return new AuthResult(false, Error: "Email already registered.");

        var account = new Account
        {
            Id = Guid.NewGuid(),
            Email = email,
            PasswordHash = _passwordHasher.Hash(password),
            CreatedAt = DateTimeOffset.UtcNow,
            SaveBlob = new SaveBlob
            {
                JsonData = """{"schemaVersion":1,"level":1,"xp":0}""",
                UpdatedAt = DateTimeOffset.UtcNow,
            },
        };
        _db.Set<Account>().Add(account);
        await _db.SaveChangesAsync(ct);
        return await IssueTokensAsync(account, ct);
    }

    public async Task<AuthResult> LoginAsync(string email, string password, CancellationToken ct = default)
    {
        email = email.Trim().ToLowerInvariant();
        var account = await _db.Set<Account>().FirstOrDefaultAsync(a => a.Email == email, ct);
        if (account == null || !_passwordHasher.Verify(password, account.PasswordHash))
            return new AuthResult(false, Error: "Invalid credentials.");
        return await IssueTokensAsync(account, ct);
    }

    public async Task<AuthResult> RefreshAsync(string refreshToken, CancellationToken ct = default)
    {
        var hash = _tokenService.HashToken(refreshToken);
        var stored = await _db.Set<RefreshToken>()
            .Include(t => t.Account)
            .FirstOrDefaultAsync(t => t.TokenHash == hash, ct);
        if (stored == null || !stored.IsActive)
            return new AuthResult(false, Error: "Invalid refresh token.");

        stored.RevokedAt = DateTimeOffset.UtcNow;
        await _db.SaveChangesAsync(ct);
        return await IssueTokensAsync(stored.Account, ct);
    }

    private async Task<AuthResult> IssueTokensAsync(Account account, CancellationToken ct)
    {
        var access = _tokenService.CreateAccessToken(account, out var expiresAt);
        var refresh = _tokenService.CreateRefreshToken();
        _db.Set<RefreshToken>().Add(new RefreshToken
        {
            Id = Guid.NewGuid(),
            AccountId = account.Id,
            TokenHash = _tokenService.HashToken(refresh),
            CreatedAt = DateTimeOffset.UtcNow,
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(30),
        });
        await _db.SaveChangesAsync(ct);
        return new AuthResult(
            true,
            account.Id,
            account.Email,
            access,
            refresh,
            expiresAt);
    }
}
