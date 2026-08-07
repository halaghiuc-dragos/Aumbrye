using System.Text.Json.Nodes;

namespace Aumbrye.Application.Abstractions;

public interface IPasswordHasher
{
    string Hash(string password);
    bool Verify(string password, string hash);
}

public interface ITokenService
{
    string CreateAccessToken(Domain.Entities.Account account, out DateTimeOffset expiresAt);
    string CreateRefreshToken();
    string HashToken(string token);
    Guid? GetAccountIdFromAccessToken(string accessToken);
}

public interface IAuthService
{
    Task<AuthResult> RegisterAsync(string email, string password, CancellationToken ct = default);
    Task<AuthResult> LoginAsync(string email, string password, CancellationToken ct = default);
    Task<AuthResult> RefreshAsync(string refreshToken, CancellationToken ct = default);
    Task<bool> LogoutAsync(Guid accountId, string refreshToken, CancellationToken ct = default);
    Task<AuthResult> AuthenticateSteamAsync(string ticketHex, uint appId, CancellationToken ct = default);
    Task<AuthResult> LinkSteamAsync(Guid accountId, string ticketHex, uint appId, CancellationToken ct = default);
}

public sealed record AuthResult(
    bool Success,
    Guid? AccountId = null,
    string? Email = null,
    string? AccessToken = null,
    string? RefreshToken = null,
    DateTimeOffset? AccessTokenExpiresAt = null,
    string? Error = null,
    int? ErrorStatus = null);

public sealed record SteamTicketValidation(
    bool Success,
    ulong? SteamId = null,
    bool VacBanned = false,
    bool PublisherBanned = false,
    string? Error = null);

public interface ISteamAuthService
{
    bool IsConfigured { get; }
    Task<SteamTicketValidation> ValidateAsync(string ticketHex, uint appId, CancellationToken ct = default);
}

public interface IRunService
{
    Task<CreateRunResult> CreateRunAsync(Guid accountId, string biomeId, int? seed, int tier, CancellationToken ct = default);
    Task<string?> GetDungeonDefinitionAsync(Guid accountId, Guid runId, int floor = 1, CancellationToken ct = default);
    Task<CompleteRunResult> CompleteRunAsync(Guid accountId, Guid runId, CompleteRunInput input, CancellationToken ct = default);
}

public sealed record CreateRunResult(
    bool Success,
    Guid RunId = default,
    int Seed = 0,
    string? BiomeId = null,
    string? DefinitionJson = null,
    string? Error = null,
    bool IsInternalError = false);

public sealed record CompleteRunInput(
    string Outcome,
    double ElapsedSeconds,
    bool BossDefeated,
    IReadOnlyList<string> LootClaimedInstanceIds,
    int Floor = 1);

public sealed record CompleteRunResult(
    bool Success,
    Guid RunId = default,
    string? Status = null,
    RunProgressionResult? Progression = null,
    string? Error = null);

public sealed record RunProgressionResult(
    int XpGained,
    int TotalXp,
    int Level,
    int TalentPointsEarned,
    IReadOnlyList<JsonObject> LootGranted,
    string EconomyNote,
    string? CharacterStateJson = null);

public sealed record SaveGetResult(bool Success, JsonObject? State = null, DateTimeOffset? UpdatedAt = null, string? Error = null);

public sealed record SavePutResult(
    bool Success,
    JsonObject? State = null,
    DateTimeOffset? UpdatedAt = null,
    bool Conflict = false,
    string? Error = null);

public interface ISaveService
{
    Task<SaveGetResult> GetCurrentAsync(Guid accountId, CancellationToken ct = default);
    Task<SavePutResult> PutCurrentAsync(Guid accountId, JsonObject state, DateTimeOffset? clientUpdatedAt, CancellationToken ct = default);
}

public sealed record DisplayNameResult(bool Success, string? DisplayName = null, string? Error = null);

public interface IAccountService
{
    Task<DisplayNameResult> UpdateDisplayNameAsync(Guid accountId, string displayName, CancellationToken ct = default);
    Task<bool> DeleteAccountAsync(Guid accountId, CancellationToken ct = default);
    Task<JsonObject?> ExportAccountAsync(Guid accountId, CancellationToken ct = default);
}

public interface IDungeonCache
{
    Task SetAsync(Guid runId, int floor, string definitionJson, TimeSpan ttl, CancellationToken ct = default);
    Task<string?> GetAsync(Guid runId, int floor, CancellationToken ct = default);
}

public interface IDungeonGenerator
{
    (string Json, string? Checksum) Generate(
        string biomeId,
        int seed,
        int tier,
        int playerLevel,
        Guid runId,
        int floorIndex = 1,
        bool isFinalFloor = false);
}
