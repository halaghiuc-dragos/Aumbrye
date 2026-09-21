namespace Aumbrye.Shared.Contracts.Leaderboards;

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
    IReadOnlyList<LeaderboardEntryResponse> Entries,
    LeaderboardCapabilitiesResponse? Capabilities = null);

public sealed record UpdateDisplayNameRequest(string DisplayName);

public sealed record UpdateDisplayNameResponse(string DisplayName);
