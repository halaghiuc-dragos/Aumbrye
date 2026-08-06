namespace Aumbrye.Procedural.Biome;

public sealed record EnemyPoolEntry(string EnemyId, int ThreatCost, int Weight);

public sealed record BossPoolEntry(string EnemyId, int ThreatCost, int Weight = 1);

public sealed record BiomeBudgets(
    int BaseEnemyThreat,
    int BaseLootValue,
    int ThreatPerTier,
    int LootPerTier);

public sealed record BiomeDefinition(
    string Id,
    string Name,
    string TemplatePrefix,
    string AssetFolder,
    int RoomCountMin,
    int RoomCountMax,
    IReadOnlyList<string> RoomTemplateIds,
    IReadOnlyList<EnemyPoolEntry> EnemyPool,
    IReadOnlyList<BossPoolEntry> BossPool,
    BiomeBudgets Budgets,
    bool RequiresSecret = true);
