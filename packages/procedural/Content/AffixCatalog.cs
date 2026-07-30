using System.Text.Json;
using System.Text.Json.Serialization;

namespace Aumbrye.Procedural.Content;

public static class AffixCatalog
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private static readonly Lazy<AffixData> Data = new(Load);

    public static IReadOnlyList<AffixDefinition> AllAffixes => Data.Value.AllAffixes;

    public static AffixRarityRules RarityRules => Data.Value.RarityRules;

    private static AffixData Load()
    {
        var affixDir = Path.Combine(ContentPaths.Root, "affixes");
        var prefixes = LoadPack(Path.Combine(affixDir, "prefixes.json"));
        var suffixes = LoadPack(Path.Combine(affixDir, "suffixes.json"));
        var rulesPath = Path.Combine(affixDir, "rarity_rules.json");
        var rulesJson = File.ReadAllText(rulesPath);
        var rules = JsonSerializer.Deserialize<AffixRarityRulesJson>(rulesJson, JsonOptions)
                    ?? throw new InvalidOperationException("Failed to parse affix rarity rules.");

        var all = prefixes.Concat(suffixes).ToList();
        return new AffixData(all, rules.ToModel());
    }

    private static List<AffixDefinition> LoadPack(string path)
    {
        var json = File.ReadAllText(path);
        var pack = JsonSerializer.Deserialize<AffixPackJson>(json, JsonOptions)
                   ?? throw new InvalidOperationException($"Failed to parse affix pack: {path}");
        return pack.Affixes.Select(a => a.ToModel()).ToList();
    }

    private sealed record AffixData(
        IReadOnlyList<AffixDefinition> AllAffixes,
        AffixRarityRules RarityRules);
}

public sealed record AffixDefinition(
    string Id,
    string DisplayName,
    string Kind,
    string Stat,
    IReadOnlyList<string> ItemTypes,
    int Weight,
    IReadOnlyDictionary<string, AffixTier> Tiers);

public sealed record AffixTier(double Min, double Max);

public sealed record AffixRarityRules(
    IReadOnlyDictionary<string, AffixCountRange> AffixCounts,
    IReadOnlyDictionary<string, int> RarityWeights);

public sealed record AffixCountRange(int Min, int Max);

internal sealed class AffixPackJson
{
    public List<AffixDefinitionJson> Affixes { get; set; } = [];
}

internal sealed class AffixDefinitionJson
{
    public string Id { get; set; } = "";
    public string DisplayName { get; set; } = "";
    public string Kind { get; set; } = "";
    public string Stat { get; set; } = "";
    public List<string> ItemTypes { get; set; } = [];
    public int Weight { get; set; } = 1;
    public Dictionary<string, AffixTierJson> Tiers { get; set; } = new();

    public AffixDefinition ToModel() => new(
        Id,
        DisplayName,
        Kind,
        Stat,
        ItemTypes,
        Weight,
        Tiers.ToDictionary(
            kv => kv.Key,
            kv => new AffixTier(kv.Value.Min, kv.Value.Max),
            StringComparer.Ordinal));
}

internal sealed class AffixTierJson
{
    public double Min { get; set; }
    public double Max { get; set; }
}

internal sealed class AffixRarityRulesJson
{
    public Dictionary<string, AffixCountRangeJson> AffixCounts { get; set; } = new();
    public Dictionary<string, int> RarityWeights { get; set; } = new();

    public AffixRarityRules ToModel() => new(
        AffixCounts.ToDictionary(
            kv => kv.Key,
            kv => new AffixCountRange(kv.Value.Min, kv.Value.Max),
            StringComparer.Ordinal),
        RarityWeights);
}

internal sealed class AffixCountRangeJson
{
    public int Min { get; set; }
    public int Max { get; set; }
}
