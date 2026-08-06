using Aumbrye.Procedural.Biome;
using Aumbrye.Procedural.Models;
using Aumbrye.Procedural.Random;
using Aumbrye.Procedural.Serialization;

namespace Aumbrye.Procedural.Generation;

/// <summary>
/// FLOOR-7.4 — final floor lobby + boss layout.
/// </summary>
public static class FinalFloorGenerator
{
    public static GenerationResult Generate(
        BiomeDefinition biome,
        int seed,
        int tier,
        int playerLevel,
        Guid runId,
        int floorIndex)
    {
        var prefix = RoomTemplateCatalog.TemplatePrefixForBiome(biome.Id);

        var rooms = new List<DungeonRoom>
        {
            new("entrance", $"{prefix}_entrance", "hub",
                new DungeonTransform(0, 0, 0, 0), ["spawn", "final_lobby"]),
            new("boss", $"{prefix}_boss", "boss",
                new DungeonTransform(0, 0, 28, 0), ["final_boss"]),
        };
        var edges = new List<DungeonEdge>
        {
            new("entrance", "boss", "door"),
        };
        var placements = new DungeonPlacements(
            Enemies: [],
            Loot:
            [
                new LootPlacement("entrance", "final_lobby_potion", new Position3(2, 0, 4),
                    [new LootItem("health_potion", 1)]),
                new LootPlacement("entrance", "final_lobby_scroll", new Position3(-2, 0, 4),
                    [new LootItem("elixir_might", 1)]),
            ],
            Puzzles: [],
            Traps: [],
            Secrets: [],
            Boss: new BossPlacement("boss", "final_boss_forgotten_castle"),
            Exit: "boss",
            Entrance: "entrance");

        var definition = new DungeonDefinition(
            SchemaVersion: 1,
            RunId: runId,
            Seed: seed,
            BiomeId: biome.Id,
            Tier: tier,
            PlayerLevelSnapshot: playerLevel,
            Rooms: rooms,
            Edges: edges,
            Placements: placements,
            Budgets: new DungeonBudgets(0, 0),
            FloorIndex: floorIndex,
            IsFinalFloor: true);

        var (json, checksum) = CanonicalJsonSerializer.Serialize(definition);
        return new GenerationResult(definition with { Checksum = checksum }, json);
    }
}
