using System.Text.Json.Nodes;
using Aumbrye.Application.Services;
using Aumbrye.Procedural.Content;
using Xunit;

namespace Aumbrye.UnitTests;

public class RunEconomyTests
{
    [Fact]
    public void Escape_GrantsFullXp()
    {
        var state = CharacterStateDefaults.Create(Guid.NewGuid());
        var curve = ProgressionCatalog.XpCurve;
        var result = ProgressionApplier.ApplyRunOutcome(
            state, "escaped", [], new Dictionary<string, LootInstanceIds.LootEntry>(), kills: 4, bossDefeated: true);
        Assert.Equal(curve.RunXp(4, true, true), result.XpGained);
        Assert.True(result.XpGained > 0);
    }

    [Fact]
    public void Death_GrantsReducedXp()
    {
        var state = CharacterStateDefaults.Create(Guid.NewGuid());
        var curve = ProgressionCatalog.XpCurve;
        var result = ProgressionApplier.ApplyRunOutcome(
            state, "died", [], new Dictionary<string, LootInstanceIds.LootEntry>(), kills: 4);
        var expected = (int)Math.Round(curve.RunXp(4, false, false) * curve.DeathXpFraction);
        Assert.Equal(expected, result.XpGained);
    }

    [Fact]
    public void Death_ClearsRunRelics()
    {
        var state = CharacterStateDefaults.Create(Guid.NewGuid());
        state["runRelics"] = new JsonArray { "knight_relic" };
        ProgressionApplier.ApplyRunOutcome(state, "died", [], new Dictionary<string, LootInstanceIds.LootEntry>());
        var relics = state["runRelics"] as JsonArray;
        Assert.NotNull(relics);
        Assert.Empty(relics);
    }

    [Fact]
    public void Escape_RollsEquipmentLoot()
    {
        var state = CharacterStateDefaults.Create(Guid.NewGuid());
        var instanceId = Guid.NewGuid().ToString();
        var lootMap = new Dictionary<string, LootInstanceIds.LootEntry>
        {
            [instanceId] = new LootInstanceIds.LootEntry("castle_sword", 1),
        };
        var result = ProgressionApplier.ApplyRunOutcome(state, "escaped", [instanceId], lootMap);
        Assert.NotEmpty(result.LootGranted);
        var instances = state["itemInstances"] as JsonObject;
        Assert.NotNull(instances);
        Assert.True(instances.ContainsKey(instanceId));
    }
}
