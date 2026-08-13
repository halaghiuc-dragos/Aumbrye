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
        // A biome with no usable pool would otherwise reach rng.NextInt(0), which throws and takes
        // the whole generation attempt with it.
        if (biome.EnemyPool.Count == 0 || biome.EnemyPool.Sum(e => Math.Max(0, e.Weight)) <= 0)
            return ([], 0.0);

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

            // Draw the room's full candidate list up front, before the budget can influence how
            // many draws happen. Consuming RNG only for enemies that fit made the entire stream
            // downstream of the first over-budget room a function of tier and player level, so
            // bumping either reshuffled every later room instead of just truncating it.
            var picks = new EnemyPoolEntry[maxPerRoom];
            for (var i = 0; i < maxPerRoom; i++)
                picks[i] = PickWeighted(biome.EnemyPool, rng);

            for (var i = 0; i < picks.Length; i++)
            {
                if (threatUsed + picks[i].ThreatCost > budget)
                    break;
                var offset = SpawnOffsets[(placements.Count + i) % SpawnOffsets.Length];
                placements.Add(new EnemyPlacement(room.SemanticId, picks[i].EnemyId, offset));
                threatUsed += picks[i].ThreatCost;
            }
        }

        return (placements, threatUsed);
    }

    private static EnemyPoolEntry PickWeighted(IReadOnlyList<EnemyPoolEntry> pool, SeededRandom rng)
    {
        var total = 0;
        foreach (var entry in pool)
            total += Math.Max(0, entry.Weight);
        if (total <= 0)
            return pool[0];

        var roll = rng.NextInt(total);
        var acc = 0;
        foreach (var entry in pool)
        {
            acc += Math.Max(0, entry.Weight);
            if (roll < acc)
                return entry;
        }
        return pool[^1];
    }
}
