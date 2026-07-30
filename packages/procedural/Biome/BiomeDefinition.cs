namespace Aumbrye.Procedural.Biome;

public sealed record EnemyPoolEntry(string EnemyId, int ThreatCost, int Weight);

public sealed record BossPoolEntry(string EnemyId, int ThreatCost);

public sealed record BiomeBudgets(
    int BaseEnemyThreat,
    int BaseLootValue,
    int ThreatPerTier,
    int LootPerTier);

public sealed record BiomeDefinition(
    string Id,
    string Name,
    int RoomCountMin,
    int RoomCountMax,
    int GridStep,
    IReadOnlyList<string> RoomTemplateIds,
    IReadOnlyList<EnemyPoolEntry> EnemyPool,
    IReadOnlyList<BossPoolEntry> BossPool,
    BiomeBudgets Budgets,
    bool RequiresSecret = true);
