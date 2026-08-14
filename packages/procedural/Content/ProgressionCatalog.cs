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

/// <summary>
/// Run XP economy and level table, mirroring the client's ProgressionService so a cloud-completed
/// run awards exactly what the local run did.
/// </summary>
public sealed record XpCurve(
    int BaseXpPerKill,
    int BossBonusXp,
    int EscapeBonusXp,
    double DeathXpFraction,
    double AbandonedXpFraction,
    int TalentPointsPerLevel,
    IReadOnlyList<LevelEntry> Levels)
{
    /// <summary>Full XP for a run before the outcome fraction is applied.</summary>
    public int RunXp(int kills, bool bossDefeated, bool escaped)
    {
        var total = Math.Max(0, kills) * BaseXpPerKill;
        if (bossDefeated)
            total += BossBonusXp;
        if (escaped)
            total += EscapeBonusXp;
        return total;
    }

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

    public static int TalentPointsForLevel(int level, int pointsPerLevel) =>
        Math.Max(0, (level - 1) * pointsPerLevel);
}

public sealed record LevelEntry(int Level, int XpRequired);

internal sealed class XpCurveJson
{
    public int BaseXpPerKill { get; set; }
    public int BossBonusXp { get; set; }
    public int EscapeBonusXp { get; set; }
    public double DeathXpFraction { get; set; }
    public double AbandonedXpFraction { get; set; }
    public int TalentPointsPerLevel { get; set; } = 1;
    public List<LevelEntryJson> Levels { get; set; } = [];

    public XpCurve ToModel() => new(
        BaseXpPerKill,
        BossBonusXp,
        EscapeBonusXp,
        DeathXpFraction,
        AbandonedXpFraction,
        TalentPointsPerLevel,
        Levels.Select(l => new LevelEntry(l.Level, l.XpRequired)).ToList());
}

internal sealed class LevelEntryJson
{
    public int Level { get; set; }
    public int XpRequired { get; set; }
}
