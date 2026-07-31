using Aumbrye.Procedural.Assignment;
using Aumbrye.Procedural.Biome;
using Aumbrye.Procedural.Models;
using Aumbrye.Procedural.Random;

namespace Aumbrye.Procedural.Placement;

/// <summary>
/// PROC-3.5 — loot, traps, boss, exit, secrets.
/// </summary>
public static class LootPlacer
{
    public static DungeonPlacements Place(
        BiomeDefinition biome,
        RoomAssignmentResult assignment,
        IReadOnlyList<EnemyPlacement> enemies,
        int tier,
        int playerLevel,
        SeededRandom rng)
    {
        var lootBudget = biome.Budgets.BaseLootValue
                         + biome.Budgets.LootPerTier * (tier - 1)
                         + playerLevel * 3;

        var loot = new List<LootPlacement>();
        var traps = new List<TrapPlacement>();
        var secrets = new List<SecretPlacement>();

        var treasureRoom = assignment.Rooms.FirstOrDefault(r => r.Type == "treasure");
        if (treasureRoom != null)
        {
            loot.Add(new LootPlacement(
                treasureRoom.SemanticId,
                "treasure_main",
                new Position3(0, 0, 0),
                ThemeLootTables.GetTreasureLoot(biome.Id)));
        }

        var secretRooms = assignment.Rooms.Where(r => r.Type == "secret").ToList();
        for (var i = 0; i < secretRooms.Count; i++)
        {
            var secretRoom = secretRooms[i];
            secrets.Add(new SecretPlacement(secretRoom.SemanticId));
            loot.Add(new LootPlacement(
                secretRoom.SemanticId,
                $"secret_vault_{i}",
                new Position3(0, 0, 0),
                ThemeLootTables.GetSecretLoot(biome.Id)));
        }

        var combatRooms = assignment.Rooms
            .Where(r => r.Type == "combat")
            .OrderBy(r => r.SemanticId, StringComparer.Ordinal)
            .ToList();
        if (combatRooms.Count > 0)
        {
            var sideRoom = combatRooms[rng.NextInt(combatRooms.Count)];
            loot.Add(new LootPlacement(
                sideRoom.SemanticId,
                $"{sideRoom.SemanticId}_side",
                new Position3(7, 0, 6),
                ThemeLootTables.GetSideLoot(biome.Id)));
        }

        if (combatRooms.Count > 1)
        {
            var armoryRoom = combatRooms.First(r => r.SemanticId != combatRooms[0].SemanticId);
            loot.Add(new LootPlacement(
                armoryRoom.SemanticId,
                $"{armoryRoom.SemanticId}_armory",
                new Position3(-4, 0, 4),
                ThemeLootTables.GetArmoryLoot(biome.Id)));
        }

        var corridor = assignment.Rooms.FirstOrDefault(r => r.Type == "corridor");
        if (corridor != null)
            traps.Add(new TrapPlacement(corridor.SemanticId, ThemeLootTables.GetCorridorTrap(biome.Id), new Position3(0, 0, 4)));

        if (combatRooms.Count > 0)
        {
            var trapRoom = combatRooms[rng.NextInt(combatRooms.Count)];
            traps.Add(new TrapPlacement(trapRoom.SemanticId, "falling_trap", new Position3(-2, 3, -5)));
        }

        var bossEntry = biome.BossPool[rng.NextInt(biome.BossPool.Count)];
        var bossRoom = assignment.Rooms.First(r => r.Type == "boss");

        return new DungeonPlacements(
            Enemies: enemies,
            Loot: loot,
            Puzzles: [],
            Traps: traps,
            Secrets: secrets,
            Boss: new BossPlacement(bossRoom.SemanticId, bossEntry.EnemyId),
            Exit: bossRoom.SemanticId,
            Entrance: assignment.Rooms.First(r => r.Type == "hub").SemanticId);
    }
}
