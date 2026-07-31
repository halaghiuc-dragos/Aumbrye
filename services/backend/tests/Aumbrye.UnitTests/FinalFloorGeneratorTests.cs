using Aumbrye.Procedural.Generation;
using Xunit;

namespace Aumbrye.UnitTests;

public class FinalFloorGeneratorTests
{
    [Fact]
    public void FinalFloor_SetsIsFinalFloorFlag()
    {
        var runId = Guid.Parse("00000000-0000-4000-8000-000000000010");
        var result = DungeonGenerator.Generate(
            "forgotten_castle", 42_001, tier: 1, playerLevel: 1, runId,
            floorIndex: 10, isFinalFloor: true);

        Assert.True(result.Definition.IsFinalFloor);
        Assert.Equal(10, result.Definition.FloorIndex);
        Assert.Equal("final_boss_forgotten_castle", result.Definition.Placements.Boss!.EnemyId);
    }

    [Fact]
    public void FloorIndex_ChangesLayoutForSameSeed()
    {
        var runId = Guid.Parse("00000000-0000-4000-8000-000000000011");
        var floor1 = DungeonGenerator.Generate("forgotten_castle", 42_001, 1, 1, runId, floorIndex: 1);
        var floor2 = DungeonGenerator.Generate("forgotten_castle", 42_001, 1, 1, runId, floorIndex: 2);

        Assert.NotEqual(floor1.Json, floor2.Json);
        Assert.Equal(1, floor1.Definition.FloorIndex);
        Assert.Equal(2, floor2.Definition.FloorIndex);
    }

    [Theory]
    [InlineData("frozen_fortress", "frozen")]
    [InlineData("dark_cathedral", "cathedral")]
    public void FinalFloor_UsesBiomeTemplatePrefix(string biomeId, string prefix)
    {
        var runId = Guid.NewGuid();
        var result = DungeonGenerator.Generate(biomeId, 99, 1, 1, runId, floorIndex: 10, isFinalFloor: true);
        Assert.Contains(result.Definition.Rooms, r => r.TemplateId.StartsWith(prefix + "_", StringComparison.Ordinal));
    }
}
