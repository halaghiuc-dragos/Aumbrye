using Aumbrye.Procedural.Biome;
using Aumbrye.Procedural.Generation;
using Aumbrye.Procedural.Layout;
using Aumbrye.Procedural.Validation;
using Xunit;

namespace Aumbrye.UnitTests;

public class DungeonGeneratorTests
{
    private static readonly BiomeLayoutRules Rules = BiomeLayoutRules.ForgottenCastle;

    [Fact]
    public void SameSeed_ProducesIdenticalJson()
    {
        var runId = Guid.Parse("00000000-0000-4000-8000-000000000001");
        var a = DungeonGenerator.Generate("forgotten_castle", 42_001, tier: 1, playerLevel: 1, runId);
        var b = DungeonGenerator.Generate("forgotten_castle", 42_001, tier: 1, playerLevel: 1, runId);
        Assert.Equal(a.Json, b.Json);
    }

    [Fact]
    public void UnknownBiome_Throws()
    {
        Assert.Throws<ArgumentException>(() =>
            DungeonGenerator.Generate("unknown_biome", 1, 1, 1, Guid.NewGuid()));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(42)]
    [InlineData(999_999)]
    public void HundredSeeds_GenerateWithoutException(int baseSeed)
    {
        for (var i = 0; i < 100; i++)
        {
            var result = DungeonGenerator.Generate(
                "forgotten_castle",
                baseSeed + i,
                tier: 1,
                playerLevel: 1,
                Guid.NewGuid());
            Assert.Contains("\"schemaVersion\":1", result.Json);
            Assert.NotNull(result.Definition.Checksum);
        }
    }

    [Fact]
    public void Boss_NotAdjacentToEntrance()
    {
        for (var seed = 0; seed < 100; seed++)
        {
            var result = DungeonGenerator.Generate("forgotten_castle", seed, 1, 1, Guid.NewGuid());
            var entrance = result.Definition.Placements.Entrance;
            var boss = result.Definition.Placements.Boss!.RoomId;
            Assert.NotEqual(entrance, boss);
            var adjacent = result.Definition.Edges.Any(e =>
                (e.From == entrance && e.To == boss) || (e.From == boss && e.To == entrance));
            Assert.False(adjacent, $"Seed {seed}: boss adjacent to entrance");
            Assert.Contains(result.Definition.Rooms, r => r.Type == "secret");
        }
    }

    [Fact]
    public void EnemyThreat_DoesNotExceedBudget()
    {
        var biome = BiomeCatalog.GetRequired("forgotten_castle");
        var budget = biome.Budgets.BaseEnemyThreat + biome.Budgets.ThreatPerTier * 0 + 1 * 5;
        for (var seed = 0; seed < 50; seed++)
        {
            var result = DungeonGenerator.Generate("forgotten_castle", seed, 1, 1, Guid.NewGuid());
            Assert.True(result.Definition.Budgets.EnemyThreat <= budget);
        }
    }

    [Fact]
    public void Definition_ContainsRequiredPlacements()
    {
        var result = DungeonGenerator.Generate("forgotten_castle", 123, 1, 1, Guid.NewGuid());
        Assert.NotNull(result.Definition.Placements.Boss);
        Assert.NotNull(result.Definition.Placements.Exit);
        Assert.False(string.IsNullOrEmpty(result.Definition.Placements.Entrance));
        Assert.NotEmpty(result.Definition.Placements.Secrets);
    }

    [Fact]
    public void ConnectivityValidator_RejectsBossAdjacentEntrance()
    {
        var graph = new LayoutGraph(
            [new LayoutNode("room_0", 0, 0), new LayoutNode("room_1", 1, 0)],
            [new LayoutEdge("room_0", "room_1")]);
        var result = ConnectivityValidator.Validate(graph, "room_0", "room_1", false, null);
        Assert.False(result.IsValid);
    }

    [Fact]
    public void CombatRooms_UseDistinctTemplatesWhenTopologyAllows()
    {
        var foundHall = false;
        var foundMultiple = false;
        for (var seed = 1; seed < 500; seed++)
        {
            var result = DungeonGenerator.Generate("forgotten_castle", seed, 1, 1, Guid.NewGuid());
            var combatTemplates = result.Definition.Rooms
                .Where(r => r.Type == "combat")
                .Select(r => r.TemplateId)
                .Distinct(StringComparer.Ordinal)
                .ToList();
            if (combatTemplates.Contains("castle_hall", StringComparer.Ordinal))
                foundHall = true;
            if (combatTemplates.Count >= 2)
                foundMultiple = true;
            if (foundHall && foundMultiple)
                break;
        }
        Assert.True(foundHall, "Expected at least one seed to place a hall-template combat room");
        Assert.True(foundMultiple, "Expected multiple combat room templates across seeds");
    }

    [Fact]
    public void RoomTransforms_AdjacentSocketsAlign()
    {
        for (var seed = 0; seed < 100; seed++)
        {
            var result = DungeonGenerator.Generate("forgotten_castle", seed, 1, 1, Guid.NewGuid());
            var rooms = result.Definition.Rooms.ToDictionary(r => r.Id, StringComparer.Ordinal);
            foreach (var edge in result.Definition.Edges)
            {
                var a = rooms[edge.From];
                var b = rooms[edge.To];
                var aSpec = RoomTemplateCatalog.GetRequired(a.TemplateId);
                var bSpec = RoomTemplateCatalog.GetRequired(b.TemplateId);
                var dx = b.Transform.X - a.Transform.X;
                var dz = b.Transform.Z - a.Transform.Z;
                const double eps = 0.01;

                if (Math.Abs(dx) > Math.Abs(dz))
                {
                    var expected = aSpec.HalfWidth + bSpec.HalfWidth;
                    Assert.True(Math.Abs(Math.Abs(dx) - expected) < eps,
                        $"Seed {seed}: {edge.From}→{edge.To} X gap {Math.Abs(dx)} expected {expected}");
                    Assert.True(Math.Abs(a.Transform.Z - b.Transform.Z) < eps,
                        $"Seed {seed}: {edge.From}→{edge.To} Z misaligned");
                }
                else
                {
                    var expected = aSpec.HalfDepth + bSpec.HalfDepth;
                    Assert.True(Math.Abs(Math.Abs(dz) - expected) < eps,
                        $"Seed {seed}: {edge.From}→{edge.To} Z gap {Math.Abs(dz)} expected {expected}");
                    Assert.True(Math.Abs(a.Transform.X - b.Transform.X) < eps,
                        $"Seed {seed}: {edge.From}→{edge.To} X misaligned");
                }
            }
        }
    }
}
