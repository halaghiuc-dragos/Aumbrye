using Aumbrye.Procedural.Assignment;
using Aumbrye.Procedural.Biome;
using Aumbrye.Procedural.Models;
using Aumbrye.Procedural.Random;

namespace Aumbrye.Procedural.Placement;

/// <summary>
/// PROC-3.4 — place enemies under threat budget.
/// </summary>
public static class EnemyPlacer
{
    private static readonly Position3[] SpawnOffsets =
    [
        new(4, 0, 2),
        new(-5, 0, -4),
        new(0, 0, 0),
        new(5, 0, -3),
        new(-4, 0, 4),
        new(3, 0, -2),
    ];

    public static (IReadOnlyList<EnemyPlacement> Enemies, double ThreatUsed) Place(
        BiomeDefinition biome,
        RoomAssignmentResult assignment,
        int tier,
        int playerLevel,
        SeededRandom rng)
    {
        var budget = biome.Budgets.BaseEnemyThreat
                     + biome.Budgets.ThreatPerTier * (tier - 1)
                     + playerLevel * 5;
        var placements = new List<EnemyPlacement>();
        var threatUsed = 0.0;
        var combatRooms = assignment.Rooms
            .Where(r => r.Type == "combat")
            .OrderBy(r => r.SemanticId, StringComparer.Ordinal)
            .ToList();

        foreach (var room in combatRooms)
        {
            var maxPerRoom = rng.NextInt(1, 3);
            for (var i = 0; i < maxPerRoom; i++)
            {
                var entry = PickWeighted(biome.EnemyPool, rng);
                if (threatUsed + entry.ThreatCost > budget)
                    break;
                var offset = SpawnOffsets[(placements.Count + i) % SpawnOffsets.Length];
                placements.Add(new EnemyPlacement(room.SemanticId, entry.EnemyId, offset));
                threatUsed += entry.ThreatCost;
            }
        }

        return (placements, threatUsed);
    }

    private static EnemyPoolEntry PickWeighted(IReadOnlyList<EnemyPoolEntry> pool, SeededRandom rng)
    {
        var total = pool.Sum(e => e.Weight);
        var roll = rng.NextInt(total);
        var acc = 0;
        foreach (var entry in pool)
        {
            acc += entry.Weight;
            if (roll < acc)
                return entry;
        }
        return pool[^1];
    }
}
