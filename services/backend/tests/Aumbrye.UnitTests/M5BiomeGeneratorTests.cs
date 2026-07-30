using Aumbrye.Procedural.Biome;
using Aumbrye.Procedural.Generation;
using Xunit;

namespace Aumbrye.UnitTests;

public class M5BiomeGeneratorTests
{
    [Theory]
    [InlineData("crystal_caverns", "crystal_entrance", "crystal_boss")]
    [InlineData("poison_swamp", "swamp_entrance", "swamp_boss")]
    public void BiomeGeneration_UsesThemeTemplatePrefix(string biomeId, string entranceTemplate, string bossTemplate)
    {
        var result = DungeonGenerator.Generate(biomeId, 42_001, tier: 1, playerLevel: 1, Guid.NewGuid());
        Assert.Contains(entranceTemplate, result.Json);
        Assert.Contains(bossTemplate, result.Json);
        Assert.Equal(biomeId, result.Definition.BiomeId);
    }

    [Fact]
    public void CrystalCaverns_LoadsWithEnemyAndBossPools()
    {
        var biome = BiomeCatalog.GetRequired("crystal_caverns");
        Assert.Equal("crystal_caverns", biome.Id);
        Assert.Contains(biome.RoomTemplateIds, id => id.StartsWith("crystal_", StringComparison.Ordinal));
        Assert.Contains(biome.EnemyPool, e => e.EnemyId == "crystal_slime");
        Assert.Contains(biome.BossPool, e => e.EnemyId == "crystal_sovereign");
    }

    [Fact]
    public void PoisonSwamp_LoadsWithEnemyAndBossPools()
    {
        var biome = BiomeCatalog.GetRequired("poison_swamp");
        Assert.Equal("poison_swamp", biome.Id);
        Assert.Contains(biome.RoomTemplateIds, id => id.StartsWith("swamp_", StringComparison.Ordinal));
        Assert.Contains(biome.EnemyPool, e => e.EnemyId == "swamp_toad");
        Assert.Contains(biome.BossPool, e => e.EnemyId == "swamp_hydra");
    }
}
