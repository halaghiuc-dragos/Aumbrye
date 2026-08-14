using Aumbrye.Procedural.Content;
using Aumbrye.Procedural.Loot;
using Xunit;

namespace Aumbrye.UnitTests;

public class AffixRollerTests
{
    [Fact]
    public void IdenticalRollSeed_ProducesIdenticalAffixes()
    {
        const string instanceId = "a1b2c3d4-e5f6-4789-a012-3456789abcde";
        const string itemId = "castle_sword";
        var seed = AffixRoller.DeriveRollSeed(instanceId);

        var first = AffixRoller.RollWithSeed(instanceId, itemId, seed);
        var second = AffixRoller.RollWithSeed(instanceId, itemId, seed);

        Assert.Equal(first.Rarity, second.Rarity);
        Assert.Equal(first.Affixes.Count, second.Affixes.Count);
        for (var i = 0; i < first.Affixes.Count; i++)
        {
            Assert.Equal(first.Affixes[i].AffixId, second.Affixes[i].AffixId);
            Assert.Equal(first.Affixes[i].Value, second.Affixes[i].Value);
        }
    }

    [Fact]
    public void CommonRarity_HasZeroAffixes()
    {
        for (var attempt = 0; attempt < 50; attempt++)
        {
            var instanceId = Guid.NewGuid().ToString();
            var rolled = AffixRoller.Roll(instanceId, "castle_sword");
            if (rolled.Rarity == ItemRarities.Common)
            {
                Assert.Empty(rolled.Affixes);
                return;
            }
        }
    }

    [Fact]
    public void RareRarity_HasTwoAffixes()
    {
        for (var attempt = 0; attempt < 200; attempt++)
        {
            var instanceId = Guid.NewGuid().ToString();
            var rolled = AffixRoller.Roll(instanceId, "castle_sword");
            if (rolled.Rarity == ItemRarities.Rare)
            {
                Assert.Equal(2, rolled.Affixes.Count);
                return;
            }
        }
    }

    [Fact]
    public void MagicRarity_HasOneAffix()
    {
        for (var attempt = 0; attempt < 200; attempt++)
        {
            var instanceId = Guid.NewGuid().ToString();
            var rolled = AffixRoller.Roll(instanceId, "castle_sword");
            if (rolled.Rarity == ItemRarities.Magic)
            {
                Assert.Single(rolled.Affixes);
                return;
            }
        }
    }

    [Fact]
    public void EpicLegendaryAumbral_AffixCountRanges_MatchRarityRules()
    {
        var rules = AffixCatalog.RarityRules.AffixCounts;
        Assert.Equal(2, rules[ItemRarities.Epic].Min);
        Assert.Equal(3, rules[ItemRarities.Epic].Max);
        Assert.Equal(3, rules[ItemRarities.Legendary].Min);
        Assert.Equal(4, rules[ItemRarities.Legendary].Max);
        Assert.Equal(4, rules[ItemRarities.Aumbral].Min);
        Assert.Equal(5, rules[ItemRarities.Aumbral].Max);
    }

    [Fact]
    public void EpicRarity_AffixCountWithinRarityRange()
    {
        for (var attempt = 0; attempt < 300; attempt++)
        {
            var rolled = AffixRoller.Roll(Guid.NewGuid().ToString(), "castle_sword");
            if (rolled.Rarity == ItemRarities.Epic)
            {
                var range = AffixCatalog.RarityRules.AffixCounts[ItemRarities.Epic];
                Assert.InRange(rolled.Affixes.Count, 0, range.Max);
                return;
            }
        }
        Assert.Fail("No epic roll in 300 attempts");
    }
}
