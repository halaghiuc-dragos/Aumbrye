using Aumbrye.Procedural.Models;

namespace Aumbrye.Procedural.Placement;

/// <summary>M5 theme-specific loot and trap tables.</summary>
public static class ThemeLootTables
{
    public static IReadOnlyList<LootItem> GetTreasureLoot(string biomeId) =>
        biomeId switch
        {
            "crystal_caverns" => [new("health_potion", 2), new("crystal_frost_ring", 1)],
            "poison_swamp" => [new("health_potion", 2), new("swamp_mire_charm", 1)],
            _ => [new("health_potion", 2), new("iron_scrap", 3)],
        };

    public static IReadOnlyList<LootItem> GetSecretLoot(string biomeId) =>
        biomeId switch
        {
            "crystal_caverns" => [new("crystal_prism_amulet", 1), new("health_potion", 3)],
            "poison_swamp" => [new("swamp_toxin_dagger", 1), new("health_potion", 3)],
            _ => [new("knight_relic", 1), new("health_potion", 3)],
        };

    public static IReadOnlyList<LootItem> GetSideLoot(string biomeId) =>
        biomeId switch
        {
            "crystal_caverns" => [new("crystal_shard_blade", 1)],
            "poison_swamp" => [new("swamp_bog_boots", 1)],
            _ => [new("iron_scrap", 2)],
        };

    public static IReadOnlyList<LootItem> GetArmoryLoot(string biomeId) =>
        biomeId switch
        {
            "crystal_caverns" => [new("crystal_shard_blade", 1)],
            "poison_swamp" => [new("swamp_toxin_dagger", 1)],
            _ => [new("castle_sword", 1)],
        };

    public static string GetCorridorTrap(string biomeId) =>
        biomeId == "poison_swamp" ? "poison_pool" : "spike_trap";
}
