using System.Text.Json;

namespace Aumbrye.Procedural.Content;

public static class ProgressionCatalog
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private static readonly Lazy<XpCurve> Curve = new(Load);

    public static XpCurve XpCurve => Curve.Value;

    private static XpCurve Load()
    {
        var path = Path.Combine(ContentPaths.Root, "progression", "xp_curve.json");
        var json = File.ReadAllText(path);
        var raw = JsonSerializer.Deserialize<XpCurveJson>(json, JsonOptions)
                  ?? throw new InvalidOperationException("Failed to parse xp curve.");
        return raw.ToModel();
    }
}

public sealed record XpCurve(
    int BaseXpPerRun,
    int TierXpBonus,
    double DeathXpFraction,
    double AbandonedXpFraction,
    IReadOnlyList<LevelEntry> Levels)
{
    public int MaxLevel => Levels.Count > 0 ? Levels[^1].Level : 1;

    public int LevelForXp(int xp)
    {
        var level = 1;
        foreach (var entry in Levels.OrderBy(l => l.Level))
        {
            if (xp < entry.XpRequired)
                break;
            level = entry.Level;
        }

        return level;
    }

    public int XpForLevel(int level)
    {
        var entry = Levels.FirstOrDefault(l => l.Level == level);
        return entry?.XpRequired ?? 0;
    }

    public int TalentPointsForLevel(int level, int pointsPerLevel) =>
        Math.Max(0, (level - 1) * pointsPerLevel);
}

public sealed record LevelEntry(int Level, int XpRequired);

internal sealed class XpCurveJson
{
    public int BaseXpPerRun { get; set; }
    public int TierXpBonus { get; set; }
    public double DeathXpFraction { get; set; }
    public double AbandonedXpFraction { get; set; }
    public List<LevelEntryJson> Levels { get; set; } = [];

    public XpCurve ToModel() => new(
        BaseXpPerRun,
        TierXpBonus,
        DeathXpFraction,
        AbandonedXpFraction,
        Levels.Select(l => new LevelEntry(l.Level, l.XpRequired)).ToList());
}

internal sealed class LevelEntryJson
{
    public int Level { get; set; }
    public int XpRequired { get; set; }
}
