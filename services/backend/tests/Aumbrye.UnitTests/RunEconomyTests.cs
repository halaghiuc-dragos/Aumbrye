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
    var result = ProgressionApplier.ApplyRunOutcome(state, "escaped", 1, [], new Dictionary<string, LootInstanceIds.LootEntry>());
    Assert.Equal(ProgressionCatalog.XpCurve.BaseXpPerRun, result.XpGained);
  }

  [Fact]
  public void Death_GrantsReducedXp()
  {
    var state = CharacterStateDefaults.Create(Guid.NewGuid());
    var result = ProgressionApplier.ApplyRunOutcome(state, "died", 1, [], new Dictionary<string, LootInstanceIds.LootEntry>());
    var expected = (int)Math.Round(ProgressionCatalog.XpCurve.BaseXpPerRun * ProgressionCatalog.XpCurve.DeathXpFraction);
    Assert.Equal(expected, result.XpGained);
  }

  [Fact]
  public void Death_ClearsRunRelics()
  {
    var state = CharacterStateDefaults.Create(Guid.NewGuid());
    state["runRelics"] = new JsonArray { "knight_relic" };
    ProgressionApplier.ApplyRunOutcome(state, "died", 1, [], new Dictionary<string, LootInstanceIds.LootEntry>());
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
    var result = ProgressionApplier.ApplyRunOutcome(state, "escaped", 1, [instanceId], lootMap);
    Assert.NotEmpty(result.LootGranted);
    var instances = state["itemInstances"] as JsonObject;
    Assert.NotNull(instances);
    Assert.True(instances.ContainsKey(instanceId));
  }
}
