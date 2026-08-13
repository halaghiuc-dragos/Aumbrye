using System.Net.Mail;
using System.Security.Cryptography;
using System.Text.Json.Nodes;
using Aumbrye.Application.Abstractions;
using Aumbrye.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace Aumbrye.Application.Services;

public class AuthService : IAuthService
{
    /// <summary>How many times a colliding generated display name is regenerated before giving up.</summary>
    private const int DisplayNameAttempts = 5;

    /// <summary>
    /// Verified against on a missing account so login costs the same wall time whether or not the
    /// address exists. Computed once at the hasher's real work factor; a hardcoded literal would
    /// drift the moment the work factor changes.
    /// </summary>
    private static string? _dummyPasswordHash;

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
        if (!IsValidEmail(email))
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
            DisplayName = GenerateWandererName(),
            PasswordHash = _passwordHasher.Hash(password),
            CreatedAt = DateTimeOffset.UtcNow,
            SaveBlob = new SaveBlob
            {
                JsonData = defaultState.ToJsonString(),
                UpdatedAt = DateTimeOffset.UtcNow,
            },
        };
        _db.Set<Account>().Add(account);

        if (!await SaveWithDisplayNameRetryAsync(account, GenerateWandererName, ct))
            return new AuthResult(false, Error: "Could not allocate a display name. Try again.", ErrorStatus: 503);

        return await IssueTokensAsync(account, familyId: null, ct);
    }

    public async Task<AuthResult> LoginAsync(string email, string password, CancellationToken ct = default)
    {
        email = email.Trim().ToLowerInvariant();
        var account = await _db.Set<Account>().FirstOrDefaultAsync(a => a.Email == email, ct);

        if (account == null || string.IsNullOrEmpty(account.Email))
        {
            // Burn an equivalent hash so a missing (or Steam-only) account is not distinguishable
            // from a wrong password by response time.
            _passwordHasher.Verify(password, DummyPasswordHash());
            return new AuthResult(false, Error: "Invalid credentials.");
        }

        if (!_passwordHasher.Verify(password, account.PasswordHash))
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

        if (!TryPinAppId(appId, out var pinnedAppId))
            return new AuthResult(false, Error: "Invalid app.", ErrorStatus: 400);

        var validation = await _steamAuth.ValidateAsync(ticketHex, pinnedAppId, ct);
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
                DisplayName = GenerateSteamName(steamId),
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

            if (!await SaveWithDisplayNameRetryAsync(account, () => GenerateSteamName(steamId), ct))
                return new AuthResult(false, Error: "Could not allocate a display name. Try again.", ErrorStatus: 503);
        }

        return await IssueTokensAsync(account, familyId: null, ct);
    }

    public async Task<AuthResult> LinkSteamAsync(Guid accountId, string ticketHex, uint appId, CancellationToken ct = default)
    {
        if (!_steamAuth.IsConfigured)
            return new AuthResult(false, Error: "Steam authentication is not configured.", ErrorStatus: 503);

        if (string.IsNullOrWhiteSpace(ticketHex) || ticketHex.Length % 2 != 0)
            return new AuthResult(false, Error: "Malformed ticket.", ErrorStatus: 400);

        if (!TryPinAppId(appId, out var pinnedAppId))
            return new AuthResult(false, Error: "Invalid app.", ErrorStatus: 400);

        var validation = await _steamAuth.ValidateAsync(ticketHex, pinnedAppId, ct);
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

    /// <summary>
    /// Resolves the app id a ticket is validated against. When the deployment pins
    /// <c>Steam:AppId</c>, a client-supplied mismatch is rejected outright and the pinned value is
    /// always what reaches Steam — otherwise a ticket minted for any other app the caller owns
    /// would authenticate here.
    /// </summary>
    private bool TryPinAppId(uint requestedAppId, out uint pinnedAppId)
    {
        var configured = _steamAuth.ConfiguredAppId;
        if (configured == null)
        {
            pinnedAppId = requestedAppId;
            return true;
        }

        pinnedAppId = configured.Value;
        return requestedAppId == 0 || requestedAppId == configured.Value;
    }

    private static bool IsValidEmail(string email)
    {
        if (string.IsNullOrWhiteSpace(email) || email.Length > 256)
            return false;
        // MailAddress accepts display-name forms like "Name <a@b.c>"; requiring Address to equal
        // the input rejects those and keeps the stored value canonical.
        return MailAddress.TryCreate(email, out var parsed)
               && string.Equals(parsed.Address, email, StringComparison.Ordinal)
               && parsed.Host.Contains('.');
    }

    /// <summary>8 hex chars is 4.3 billion values — collisions stay rare well past launch scale.</summary>
    private static string GenerateWandererName() =>
        "Wanderer-" + Convert.ToHexString(RandomNumberGenerator.GetBytes(4)).ToLowerInvariant();

    /// <summary>
    /// The LAST 9 digits of a SteamID64. The leading digits are the near-constant 7656119 prefix,
    /// so truncating from the front produced the same name for essentially every Steam account.
    /// </summary>
    private static string GenerateSteamName(ulong steamId) => $"Steam-{steamId % 1_000_000_000}";

    private string DummyPasswordHash() =>
        _dummyPasswordHash ??= _passwordHasher.Hash("aumbrye-login-timing-equalizer");

    /// <summary>
    /// Persists an account, regenerating its display name when the unique index rejects it.
    /// Generated names collide by birthday paradox long before they exhaust the namespace, so a
    /// pre-check alone is not enough — two concurrent registrations can pass it and still clash.
    /// </summary>
    private async Task<bool> SaveWithDisplayNameRetryAsync(
        Account account,
        Func<string> regenerate,
        CancellationToken ct)
    {
        for (var attempt = 0; attempt < DisplayNameAttempts; attempt++)
        {
            try
            {
                await _db.SaveChangesAsync(ct);
                return true;
            }
            catch (DbUpdateException) when (attempt < DisplayNameAttempts - 1)
            {
                // Widen the namespace on each retry so a genuinely saturated prefix still resolves.
                account.DisplayName = Truncate(
                    $"{regenerate()}-{Convert.ToHexString(RandomNumberGenerator.GetBytes(2)).ToLowerInvariant()}",
                    32);
            }
        }

        return false;
    }

    private static string Truncate(string value, int maxLength) =>
        value.Length <= maxLength ? value : value[..maxLength];

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
    private readonly ILeaderboardStore _leaderboards;

    public AccountService(DbContext db, ILeaderboardStore leaderboards)
    {
        _db = db;
        _leaderboards = leaderboards;
    }

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

        // Leaderboards live outside the relational cascade, so deleting the row alone would leave
        // the player's display name and account id publicly listed forever.
        await _leaderboards.RemoveAccountAsync(accountId, ct);

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
            ["elapsedSeconds"] = r.ElapsedSeconds,
        }).ToArray<JsonNode?>();

        var leaderboardEntries = (await _leaderboards.GetEntriesForAccountAsync(accountId, ct))
            .Select(e => (JsonNode?)new JsonObject
            {
                ["biomeId"] = e.BiomeId,
                ["tier"] = e.Tier,
                ["elapsedSeconds"] = e.ElapsedSeconds,
                ["submittedAt"] = e.SubmittedAt.ToString("O"),
                ["displayName"] = e.DisplayName,
            })
            .ToArray();

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
            ["leaderboardEntries"] = new JsonArray(leaderboardEntries),
            ["refreshTokenCount"] = account.RefreshTokens.Count,
        };
    }
}
