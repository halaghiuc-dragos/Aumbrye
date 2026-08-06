using Aumbrye.Procedural.Content;
using Xunit;

namespace Aumbrye.UnitTests;

public class XpCurveTests
{
    [Fact]
    public void LevelForXp_UsesCurveTable()
    {
        var curve = ProgressionCatalog.XpCurve;
        Assert.Equal(1, curve.LevelForXp(0));
        Assert.Equal(1, curve.LevelForXp(99));
        Assert.Equal(2, curve.LevelForXp(100));
        Assert.Equal(3, curve.LevelForXp(250));
    }

    [Fact]
    public void DeathXpFraction_IsConfigured()
    {
        Assert.Equal(0.5, ProgressionCatalog.XpCurve.DeathXpFraction);
    }

    [Fact]
    public void RunXp_IncludesTierBonus()
    {
        var curve = ProgressionCatalog.XpCurve;
        var tier1 = curve.BaseXpPerRun;
        var tier2 = curve.BaseXpPerRun + curve.TierXpBonus;
        Assert.True(tier2 > tier1);
    }

    [Theory]
    [InlineData(5, 4)]
    [InlineData(10, 9)]
    public void TalentPointsForLevel_MatchesPointsPerLevel(int level, int expectedPoints)
    {
        var tree = TalentCatalog.GetTree();
        var points = XpCurve.TalentPointsForLevel(level, tree.TalentPointsPerLevel);
        Assert.Equal(expectedPoints, points);
    }
}
