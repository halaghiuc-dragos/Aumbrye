namespace Aumbrye.Shared.Contracts.Runs;

public sealed record CreateRunRequest(string BiomeId, int? Seed, int Tier = 1);

public sealed record CreateRunResponse(
    Guid RunId,
    int Seed,
    string BiomeId,
    string DefinitionJson);

public sealed record CompleteRunRequest(
    string Outcome,
    double ElapsedSeconds,
    bool BossDefeated,
    IReadOnlyList<string>? LootClaimedInstanceIds);

public sealed record CompleteRunResponse(Guid RunId, string Status);

public sealed record RunResultRequest(
    int SchemaVersion,
    Guid RunId,
    string Outcome,
    double ElapsedSeconds,
    bool BossDefeated,
    IReadOnlyList<string> LootClaimedInstanceIds,
    string? ClientChecksum);
