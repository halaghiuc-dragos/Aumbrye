using System.Text.Json;
using System.Text.Json.Nodes;
using Aumbrye.Application.Abstractions;
using Aumbrye.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace Aumbrye.Application.Services;

public class AuthService : IAuthService
{
    private readonly DbContext _db;
    private readonly IPasswordHasher _passwordHasher;
    private readonly ITokenService _tokenService;
    private readonly ISteamAuthService _steamAuth;

    public AuthService(
        DbContext db,
        IPasswordHasher passwordHasher,
        ITokenService tokenService,
        ISteamAuthService steamAuth)
    {
        _db = db;
        _passwordHasher = passwordHasher;
        _tokenService = tokenService;
        _steamAuth = steamAuth;
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

        var accountId = Guid.NewGuid();
        var defaultState = CharacterStateDefaults.Create(accountId);
        var account = new Account
        {
            Id = accountId,
            Email = email,
            DisplayName = "Wanderer-" + accountId.ToString("N")[..6],
            PasswordHash = _passwordHasher.Hash(password),
            CreatedAt = DateTimeOffset.UtcNow,
            SaveBlob = new SaveBlob
            {
                JsonData = defaultState.ToJsonString(),
                UpdatedAt = DateTimeOffset.UtcNow,
            },
        };
        _db.Set<Account>().Add(account);
        await _db.SaveChangesAsync(ct);
        return await IssueTokensAsync(account, familyId: null, ct);
    }

    public async Task<AuthResult> LoginAsync(string email, string password, CancellationToken ct = default)
    {
        email = email.Trim().ToLowerInvariant();
        var account = await _db.Set<Account>().FirstOrDefaultAsync(a => a.Email == email, ct);
        if (account == null || string.IsNullOrEmpty(account.Email) || !_passwordHasher.Verify(password, account.PasswordHash))
            return new AuthResult(false, Error: "Invalid credentials.");
        return await IssueTokensAsync(account, familyId: null, ct);
    }

    public async Task<AuthResult> RefreshAsync(string refreshToken, CancellationToken ct = default)
    {
        var hash = _tokenService.HashToken(refreshToken);
        var stored = await _db.Set<RefreshToken>()
            .Include(t => t.Account)
            .FirstOrDefaultAsync(t => t.TokenHash == hash, ct);
        if (stored == null)
            return new AuthResult(false, Error: "Invalid refresh token.");

        if (stored.RevokedAt != null)
        {
            await RevokeFamilyAsync(stored.FamilyId, ct);
            return new AuthResult(false, Error: "Invalid refresh token.");
        }

        if (!stored.IsActive)
            return new AuthResult(false, Error: "Invalid refresh token.");

        var newRefresh = _tokenService.CreateRefreshToken();
        var newHash = _tokenService.HashToken(newRefresh);
        stored.RevokedAt = DateTimeOffset.UtcNow;
        stored.ReplacedByTokenHash = newHash;

        var access = _tokenService.CreateAccessToken(stored.Account, out var expiresAt);
        _db.Set<RefreshToken>().Add(new RefreshToken
        {
            Id = Guid.NewGuid(),
            AccountId = stored.Account.Id,
            FamilyId = stored.FamilyId,
            TokenHash = newHash,
            CreatedAt = DateTimeOffset.UtcNow,
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(30),
        });
        await _db.SaveChangesAsync(ct);

        return new AuthResult(
            true,
            stored.Account.Id,
            stored.Account.Email ?? string.Empty,
            access,
            newRefresh,
            expiresAt);
    }

    public async Task<bool> LogoutAsync(Guid accountId, string refreshToken, CancellationToken ct = default)
    {
        var hash = _tokenService.HashToken(refreshToken);
        var stored = await _db.Set<RefreshToken>()
            .FirstOrDefaultAsync(t => t.TokenHash == hash && t.AccountId == accountId, ct);
        if (stored == null || stored.RevokedAt != null)
            return false;

        stored.RevokedAt = DateTimeOffset.UtcNow;
        await _db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<AuthResult> AuthenticateSteamAsync(string ticketHex, uint appId, CancellationToken ct = default)
    {
        if (!_steamAuth.IsConfigured)
            return new AuthResult(false, Error: "Steam authentication is not configured.", ErrorStatus: 503);

        if (string.IsNullOrWhiteSpace(ticketHex) || ticketHex.Length % 2 != 0)
            return new AuthResult(false, Error: "Malformed ticket.", ErrorStatus: 400);

        var validation = await _steamAuth.ValidateAsync(ticketHex, appId, ct);
        if (!validation.Success || validation.SteamId == null)
            return new AuthResult(false, Error: validation.Error ?? "Steam rejected the ticket.", ErrorStatus: 401);
        if (validation.VacBanned || validation.PublisherBanned)
            return new AuthResult(false, Error: "Steam rejected the ticket.", ErrorStatus: 401);

        var steamId = validation.SteamId.Value;
        var account = await _db.Set<Account>()
            .Include(a => a.SaveBlob)
            .FirstOrDefaultAsync(a => a.SteamId == steamId, ct);
        if (account == null)
        {
            var accountId = Guid.NewGuid();
            var defaultState = CharacterStateDefaults.Create(accountId);
            account = new Account
            {
                Id = accountId,
                Email = null,
                DisplayName = $"Steam-{steamId}"[..Math.Min(15, $"Steam-{steamId}".Length)],
                PasswordHash = string.Empty,
                SteamId = steamId,
                SteamLinkedAt = DateTimeOffset.UtcNow,
                CreatedAt = DateTimeOffset.UtcNow,
                SaveBlob = new SaveBlob
                {
                    JsonData = defaultState.ToJsonString(),
                    UpdatedAt = DateTimeOffset.UtcNow,
                },
            };
            _db.Set<Account>().Add(account);
            await _db.SaveChangesAsync(ct);
        }

        return await IssueTokensAsync(account, familyId: null, ct);
    }

    public async Task<AuthResult> LinkSteamAsync(Guid accountId, string ticketHex, uint appId, CancellationToken ct = default)
    {
        if (!_steamAuth.IsConfigured)
            return new AuthResult(false, Error: "Steam authentication is not configured.", ErrorStatus: 503);

        if (string.IsNullOrWhiteSpace(ticketHex) || ticketHex.Length % 2 != 0)
            return new AuthResult(false, Error: "Malformed ticket.", ErrorStatus: 400);

        var validation = await _steamAuth.ValidateAsync(ticketHex, appId, ct);
        if (!validation.Success || validation.SteamId == null)
            return new AuthResult(false, Error: validation.Error ?? "Steam rejected the ticket.", ErrorStatus: 401);
        if (validation.VacBanned || validation.PublisherBanned)
            return new AuthResult(false, Error: "Steam rejected the ticket.", ErrorStatus: 401);

        var steamId = validation.SteamId.Value;
        var existing = await _db.Set<Account>()
            .FirstOrDefaultAsync(a => a.SteamId == steamId && a.Id != accountId, ct);
        if (existing != null)
            return new AuthResult(false, Error: "Steam account already linked.", ErrorStatus: 409);

        var account = await _db.Set<Account>().FirstOrDefaultAsync(a => a.Id == accountId, ct);
        if (account == null)
            return new AuthResult(false, Error: "Account not found.", ErrorStatus: 404);

        account.SteamId = steamId;
        account.SteamLinkedAt = DateTimeOffset.UtcNow;
        await _db.SaveChangesAsync(ct);
        return new AuthResult(true, account.Id, account.Email);
    }

    private async Task RevokeFamilyAsync(Guid familyId, CancellationToken ct)
    {
        var tokens = await _db.Set<RefreshToken>()
            .Where(t => t.FamilyId == familyId && t.RevokedAt == null)
            .ToListAsync(ct);
        var now = DateTimeOffset.UtcNow;
        foreach (var token in tokens)
            token.RevokedAt = now;
        await _db.SaveChangesAsync(ct);
    }

    private async Task<AuthResult> IssueTokensAsync(Account account, Guid? familyId, CancellationToken ct)
    {
        var access = _tokenService.CreateAccessToken(account, out var expiresAt);
        var refresh = _tokenService.CreateRefreshToken();
        var tokenId = Guid.NewGuid();
        var family = familyId ?? tokenId;
        _db.Set<RefreshToken>().Add(new RefreshToken
        {
            Id = tokenId,
            AccountId = account.Id,
            FamilyId = family,
            TokenHash = _tokenService.HashToken(refresh),
            CreatedAt = DateTimeOffset.UtcNow,
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(30),
        });
        await _db.SaveChangesAsync(ct);
        return new AuthResult(
            true,
            account.Id,
            account.Email ?? string.Empty,
            access,
            refresh,
            expiresAt);
    }
}

public class AccountService : IAccountService
{
    private readonly DbContext _db;

    public AccountService(DbContext db) => _db = db;

    public async Task<DisplayNameResult> UpdateDisplayNameAsync(
        Guid accountId,
        string displayName,
        CancellationToken ct = default)
    {
        displayName = displayName.Trim();
        if (displayName.Length is < 1 or > 32)
            return new DisplayNameResult(false, Error: "Display name must be 1–32 characters.");

        var account = await _db.Set<Account>().FirstOrDefaultAsync(a => a.Id == accountId, ct);
        if (account == null)
            return new DisplayNameResult(false, Error: "Account not found.");

        var taken = await _db.Set<Account>()
            .AnyAsync(a => a.DisplayName == displayName && a.Id != accountId, ct);
        if (taken)
            return new DisplayNameResult(false, Error: "Display name already taken.");

        account.DisplayName = displayName;
        await _db.SaveChangesAsync(ct);
        return new DisplayNameResult(true, displayName);
    }

    public async Task<bool> DeleteAccountAsync(Guid accountId, CancellationToken ct = default)
    {
        var account = await _db.Set<Account>()
            .Include(a => a.RefreshTokens)
            .Include(a => a.Runs)
            .Include(a => a.SaveBlob)
            .FirstOrDefaultAsync(a => a.Id == accountId, ct);
        if (account == null)
            return false;

        _db.Set<Account>().Remove(account);
        await _db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<JsonObject?> ExportAccountAsync(Guid accountId, CancellationToken ct = default)
    {
        var account = await _db.Set<Account>()
            .Include(a => a.SaveBlob)
            .Include(a => a.Runs)
            .Include(a => a.RefreshTokens)
            .AsNoTracking()
            .FirstOrDefaultAsync(a => a.Id == accountId, ct);
        if (account == null)
            return null;

        var runs = account.Runs.Select(r => new JsonObject
        {
            ["id"] = r.Id.ToString(),
            ["biomeId"] = r.BiomeId,
            ["seed"] = r.Seed,
            ["tier"] = r.Tier,
            ["status"] = r.Status.ToString(),
            ["createdAt"] = r.CreatedAt.ToString("O"),
            ["completedAt"] = r.CompletedAt?.ToString("O"),
        }).ToArray<JsonNode?>();

        return new JsonObject
        {
            ["accountId"] = account.Id.ToString(),
            ["email"] = account.Email,
            ["displayName"] = account.DisplayName,
            ["createdAt"] = account.CreatedAt.ToString("O"),
            ["save"] = account.SaveBlob == null
                ? null
                : JsonNode.Parse(account.SaveBlob.JsonData),
            ["runs"] = new JsonArray(runs),
            ["refreshTokenCount"] = account.RefreshTokens.Count,
        };
    }
}
