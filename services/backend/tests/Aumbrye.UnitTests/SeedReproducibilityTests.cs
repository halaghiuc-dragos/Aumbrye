using System.Text.Json;
using System.Text.Json.Nodes;
using Aumbrye.Procedural.Generation;
using Xunit;

namespace Aumbrye.UnitTests;

/// <summary>
/// Verifies cross-machine seed sharing: same input seed → same layout/enemies/loot
/// regardless of runId (runId only affects loot instanceId metadata).
/// </summary>
public class SeedReproducibilityTests
{
    [Theory]
    [InlineData(42001)]
    [InlineData(123456)]
    [InlineData(9_999_999)]
    public void SameSeed_DifferentRunIds_ProduceEquivalentGameplay(int seed)
    {
        var a = DungeonGenerator.Generate("forgotten_castle", seed, 1, 1, Guid.NewGuid());
        var b = DungeonGenerator.Generate("forgotten_castle", seed, 1, 1, Guid.NewGuid());

        Assert.Equal(NormalizeGameplayJson(a.Json), NormalizeGameplayJson(b.Json));
    }

    [Fact]
    public void DifferentSeeds_UsuallyProduceDifferentLayouts()
    {
        var a = NormalizeGameplayJson(
            DungeonGenerator.Generate("forgotten_castle", 111, 1, 1, Guid.NewGuid()).Json);
        var b = NormalizeGameplayJson(
            DungeonGenerator.Generate("forgotten_castle", 222, 1, 1, Guid.NewGuid()).Json);
        Assert.NotEqual(a, b);
    }

    private static string NormalizeGameplayJson(string json)
    {
        var root = JsonNode.Parse(json)!.AsObject();
        root.Remove("runId");
        root.Remove("checksum");

        var placements = root["placements"]?.AsObject();
        if (placements?["loot"] is JsonArray loot)
        {
            foreach (var chestNode in loot)
            {
                if (chestNode?["items"] is not JsonArray items)
                    continue;
                foreach (var itemNode in items)
                    itemNode?.AsObject().Remove("instanceId");
            }
        }

        return root.ToJsonString(new JsonSerializerOptions { WriteIndented = false });
    }
}
