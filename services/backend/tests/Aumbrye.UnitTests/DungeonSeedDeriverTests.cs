using Aumbrye.Procedural.Generation;
using Xunit;

namespace Aumbrye.UnitTests;

public class DungeonSeedDeriverTests
{
    [Theory]
    [InlineData(42001, 1, 42001)]
    [InlineData(42001, 2, 42001 ^ (2 * DungeonSeedDeriver.TierSeedMultiplier))]
    public void DeriveTierSeed_MapsBaseSeedPerTier(int baseSeed, int tier, int expected)
    {
        Assert.Equal(expected, DungeonSeedDeriver.DeriveTierSeed(baseSeed, tier));
    }

    [Fact]
    public void MixFloorSeed_FloorOne_IsIdentity()
    {
        Assert.Equal(12345, DungeonSeedDeriver.MixFloorSeed(12345, 1));
    }

    [Fact]
    public void MixFloorSeed_MatchesFixtureSample()
    {
        Assert.Equal(967749581, DungeonSeedDeriver.MixFloorSeed(1, 2));
    }

    [Fact]
    public void GenerationSeed_Tier1Floor1_EqualsBaseSeed()
    {
        Assert.Equal(42_001, DungeonSeedDeriver.GenerationSeed(42_001, 1, 1));
    }

    [Fact]
    public void GenerationSeed_IsStableAcrossProcesses()
    {
        const int expected = 61_764_214;
        Assert.Equal(expected, DungeonSeedDeriver.GenerationSeed(12345, 2, 3));
    }

    [Fact]
    public void GenerationSeed_IsDeterministicForSameInputs()
    {
        var a = DungeonSeedDeriver.GenerationSeed(12345, 2, 3);
        var b = DungeonSeedDeriver.GenerationSeed(12345, 2, 3);
        Assert.Equal(a, b);
        Assert.NotEqual(
            DungeonSeedDeriver.GenerationSeed(12345, 1, 1),
            DungeonSeedDeriver.GenerationSeed(12345, 2, 1));
    }
}
