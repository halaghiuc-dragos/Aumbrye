using System.Text.Json;

namespace Aumbrye.Procedural.Content;

/// <summary>
/// Loads enemy definitions from content/enemies and content/bosses JSON files.
/// </summary>
public static class EnemyCatalog
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private static readonly Lazy<Dictionary<string, EnemyDefinition>> ById = new(LoadAll);

    private static readonly Dictionary<string, string> LegacyAliases = new(StringComparer.Ordinal)
    {
        ["castle_knight"] = "boss_castle_knight",
    };

    public static EnemyDefinition GetRequired(string enemyId) =>
        ById.Value.TryGetValue(ResolveId(enemyId), out var def)
            ? def
            : throw new ArgumentException($"Unknown enemy id: {enemyId}", nameof(enemyId));

    public static bool TryGet(string enemyId, out EnemyDefinition? definition) =>
        ById.Value.TryGetValue(ResolveId(enemyId), out definition);

    private static string ResolveId(string enemyId) =>
        LegacyAliases.TryGetValue(enemyId, out var resolved) ? resolved : enemyId;

    public static int GetThreatCost(string enemyId) => GetRequired(enemyId).ThreatCost;

    private static Dictionary<string, EnemyDefinition> LoadAll()
    {
        var defs = new Dictionary<string, EnemyDefinition>(StringComparer.Ordinal);
        LoadDirectory(ContentPaths.Enemies, defs);
        LoadDirectory(ContentPaths.Bosses, defs);
        return defs;
    }

    private static void LoadDirectory(string directory, Dictionary<string, EnemyDefinition> defs)
    {
        if (!Directory.Exists(directory))
            return;

        foreach (var file in Directory.EnumerateFiles(directory, "*.json"))
        {
            var json = File.ReadAllText(file);
            var raw = JsonSerializer.Deserialize<EnemyDefinitionJson>(json, JsonOptions)
                      ?? throw new InvalidOperationException($"Failed to parse enemy file: {file}");
            if (string.IsNullOrWhiteSpace(raw.Id))
                throw new InvalidOperationException($"Enemy file missing id: {file}");

            defs[raw.Id] = new EnemyDefinition(
                raw.Id,
                raw.Name ?? raw.Id,
                raw.ThreatCost ?? 0,
                Path.GetRelativePath(ContentPaths.Root, file).Replace('\\', '/'));
        }
    }

    private sealed record EnemyDefinitionJson(
        string Id,
        string? Name,
        int? ThreatCost);
}

public sealed record EnemyDefinition(
    string Id,
    string Name,
    int ThreatCost,
    string ContentPath);
