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
