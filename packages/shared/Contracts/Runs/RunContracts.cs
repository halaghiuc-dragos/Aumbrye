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
    IReadOnlyList<string>? LootClaimedInstanceIds,
    int Floor = 1,
    int Kills = 0);

public sealed record CompleteRunResponse(
    Guid RunId,
    string Status,
    CompleteRunProgressionResponse? Progression = null);

public sealed record CompleteRunProgressionResponse(
    int XpGained,
    int TotalXp,
    int Level,
    int TalentPointsEarned,
    IReadOnlyList<LootGrantedResponse> LootGranted,
    string EconomyNote,
    string? CharacterStateJson = null);

public sealed record LootGrantedResponse(
    string? InstanceId,
    string? ItemDefId,
    string? ItemId,
    string? Rarity,
    int? AffixCount,
    int? Quantity);
