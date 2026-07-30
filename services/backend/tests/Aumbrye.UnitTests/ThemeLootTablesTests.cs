using Aumbrye.Procedural.Placement;
using Xunit;

namespace Aumbrye.UnitTests;

public class ThemeLootTablesTests
{
    [Theory]
    [InlineData("crystal_caverns", "crystal_frost_ring")]
    [InlineData("poison_swamp", "swamp_mire_charm")]
    [InlineData("forgotten_castle", "iron_scrap")]
    public void TreasureLoot_ContainsThemeItem(string biomeId, string expectedItemId)
    {
        var loot = ThemeLootTables.GetTreasureLoot(biomeId);
        Assert.Contains(loot, item => item.ItemId == expectedItemId);
    }

    [Theory]
    [InlineData("crystal_caverns", "crystal_prism_amulet")]
    [InlineData("poison_swamp", "swamp_toxin_dagger")]
    [InlineData("forgotten_castle", "knight_relic")]
    public void SecretLoot_ContainsThemeUnique(string biomeId, string expectedItemId)
    {
        var loot = ThemeLootTables.GetSecretLoot(biomeId);
        Assert.Contains(loot, item => item.ItemId == expectedItemId);
    }

    [Fact]
    public void SwampCorridorTrap_IsPoisonPool()
    {
        Assert.Equal("poison_pool", ThemeLootTables.GetCorridorTrap("poison_swamp"));
        Assert.Equal("spike_trap", ThemeLootTables.GetCorridorTrap("crystal_caverns"));
        Assert.Equal("spike_trap", ThemeLootTables.GetCorridorTrap("forgotten_castle"));
    }
}
