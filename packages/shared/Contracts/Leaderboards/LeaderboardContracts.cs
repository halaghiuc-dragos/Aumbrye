namespace Aumbrye.Shared.Contracts.Leaderboards;

/// <summary>
/// Server-owned compatibility values for comparable ranked boards.  A new content or balance
/// contract must receive a new version so its records cannot be mixed with an older ruleset.
/// </summary>
public static class RankedLeaderboardContract
{
    public const string Ruleset = "standard-v1";
    public const string RulesVersion = "2026.09.15";
    // A leaderboard content contract identifies the accepted game build as well as content and
    // balance rules. This keeps otherwise identical seeds separate across app/content releases.
    public const string ContentVersion = "client-" + ApiVersions.ExpectedClientVersion
        + "-content-" + ApiVersions.ExpectedContentVersion + "-rules-" + RulesVersion;
}

public sealed record SubmitLeaderboardRequest(Guid RunId, bool OptIn);

public sealed record SubmitLeaderboardResponse(bool Submitted, int? Rank = null, string? Reason = null);

public sealed record LeaderboardEntryResponse(
    Guid AccountId,
    string DisplayName,
    double ElapsedSeconds,
    DateTimeOffset SubmittedAt);

public sealed record LeaderboardBiomeOption(string Id, string Label);

public sealed record LeaderboardCapabilitiesResponse(
    string RulesVersion,
    int MinimumTier,
    int MaximumTier,
    IReadOnlyList<LeaderboardBiomeOption> Biomes);

public sealed record LeaderboardPageResponse(
    string BiomeId,
    int Tier,
    int Seed,
    int PlayerLevel,
    string ClientVersion,
    string Ruleset,
    string ContentVersion,
    IReadOnlyList<LeaderboardEntryResponse> Entries,
    LeaderboardCapabilitiesResponse? Capabilities = null);

public sealed record UpdateDisplayNameRequest(string DisplayName);

public sealed record UpdateDisplayNameResponse(string DisplayName);
