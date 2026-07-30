using System.Text.Json;
using System.Text.Json.Serialization;
using Aumbrye.Procedural.Content;

namespace Aumbrye.Procedural.Biome;

public static class BiomeCatalog
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private static readonly Lazy<Dictionary<string, BiomeDefinition>> ById = new(LoadAll);

    public static BiomeDefinition GetRequired(string biomeId)
    {
        if (ById.Value.TryGetValue(biomeId, out var biome))
            return biome;
        throw new ArgumentException($"Unknown biome id: {biomeId}", nameof(biomeId));
    }

    public static bool TryGet(string biomeId, out BiomeDefinition? biome) =>
        ById.Value.TryGetValue(biomeId, out biome);

    private static Dictionary<string, BiomeDefinition> LoadAll()
    {
        var biomes = new Dictionary<string, BiomeDefinition>(StringComparer.Ordinal);
        if (!Directory.Exists(ContentPaths.Biomes))
            return biomes;

        foreach (var file in Directory.EnumerateFiles(ContentPaths.Biomes, "*.json"))
        {
            var json = File.ReadAllText(file);
            var raw = JsonSerializer.Deserialize<BiomeDefinitionJson>(json, JsonOptions)
                      ?? throw new InvalidOperationException($"Failed to parse biome file: {file}");
            if (string.IsNullOrWhiteSpace(raw.Id))
                throw new InvalidOperationException($"Biome file missing id: {file}");

            var enemyPool = raw.EnemyPool?
                .Select(entry => new EnemyPoolEntry(
                    entry.EnemyId,
                    EnemyCatalog.GetThreatCost(entry.EnemyId),
                    entry.Weight))
                .ToList()
                ?? [];

            var bossPool = raw.BossPool?
                .Select(entry => new BossPoolEntry(
                    entry.EnemyId,
                    EnemyCatalog.GetThreatCost(entry.EnemyId)))
                .ToList()
                ?? [];

            var budgets = raw.Budgets ?? new BiomeBudgetsJson();
            biomes[raw.Id] = new BiomeDefinition(
                raw.Id,
                raw.Name ?? raw.Id,
                raw.RoomCount?.Min ?? 6,
                raw.RoomCount?.Max ?? 10,
                raw.GridStep,
                raw.RoomTemplateIds ?? [],
                enemyPool,
                bossPool,
                new BiomeBudgets(
                    budgets.BaseEnemyThreat,
                    budgets.BaseLootValue,
                    budgets.ThreatPerTier,
                    budgets.LootPerTier),
                raw.RequiresSecret);
        }

        return biomes;
    }

    private sealed record BiomeDefinitionJson(
        string Id,
        string? Name,
        RoomCountJson? RoomCount,
        int GridStep,
        IReadOnlyList<string>? RoomTemplateIds,
        IReadOnlyList<EnemyPoolEntryJson>? EnemyPool,
        IReadOnlyList<BossPoolEntryJson>? BossPool,
        BiomeBudgetsJson? Budgets,
        bool RequiresSecret = true);

    private sealed record RoomCountJson(int Min, int Max);

    private sealed record EnemyPoolEntryJson(string EnemyId, int Weight);

    private sealed record BossPoolEntryJson(string EnemyId);

    private sealed record BiomeBudgetsJson(
        [property: JsonPropertyName("baseEnemyThreat")] int BaseEnemyThreat = 100,
        [property: JsonPropertyName("baseLootValue")] int BaseLootValue = 60,
        [property: JsonPropertyName("threatPerTier")] int ThreatPerTier = 20,
        [property: JsonPropertyName("lootPerTier")] int LootPerTier = 10);
}
