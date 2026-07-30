using Aumbrye.Procedural.Biome;
using Xunit;

namespace Aumbrye.UnitTests;

public class BiomeCatalogTests
{
    [Fact]
    public void ForgottenCastle_LoadsWithPoolsAndBudgets()
    {
        var biome = BiomeCatalog.GetRequired("forgotten_castle");
        Assert.Equal("forgotten_castle", biome.Id);
        Assert.InRange(biome.RoomCountMin, 1, biome.RoomCountMax);
        Assert.NotEmpty(biome.RoomTemplateIds);
        Assert.NotEmpty(biome.EnemyPool);
        Assert.NotEmpty(biome.BossPool);
        Assert.True(biome.Budgets.BaseEnemyThreat > 0);
        Assert.True(biome.RequiresSecret);
    }

    [Fact]
    public void ForgottenCastle_EnemyPool_HasPositiveWeights()
    {
        var biome = BiomeCatalog.GetRequired("forgotten_castle");
        foreach (var entry in biome.EnemyPool)
        {
            Assert.False(string.IsNullOrWhiteSpace(entry.EnemyId));
            Assert.True(entry.Weight > 0);
            Assert.True(entry.ThreatCost >= 0);
        }
    }

    [Fact]
    public void UnknownBiome_Throws()
    {
        Assert.False(BiomeCatalog.TryGet("nonexistent_biome", out _));
        Assert.Throws<ArgumentException>(() => BiomeCatalog.GetRequired("nonexistent_biome"));
    }
}
