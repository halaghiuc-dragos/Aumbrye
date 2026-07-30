using System.Text.Json;

namespace Aumbrye.Procedural.Content;

/// <summary>
/// Loads item definitions from content/items category subfolders.
/// </summary>
public static class ItemCatalog
{
    private static readonly string[] CategoryDirs = ["equipment", "consumables", "materials"];

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private static readonly Lazy<Dictionary<string, ItemDefinition>> ById = new(LoadAll);

    public static ItemDefinition GetRequired(string itemId) =>
        ById.Value.TryGetValue(itemId, out var def)
            ? def
            : throw new ArgumentException($"Unknown item id: {itemId}", nameof(itemId));

    public static bool TryGet(string itemId, out ItemDefinition? definition) =>
        ById.Value.TryGetValue(itemId, out definition);

    public static int GetLootValue(string itemId) =>
        TryGet(itemId, out var def) && def is not null ? def.LootValue : 1;

    private static Dictionary<string, ItemDefinition> LoadAll()
    {
        var defs = new Dictionary<string, ItemDefinition>(StringComparer.Ordinal);
        foreach (var category in CategoryDirs)
            LoadDirectory(Path.Combine(ContentPaths.Items, category), defs);
        return defs;
    }

    private static void LoadDirectory(string directory, Dictionary<string, ItemDefinition> defs)
    {
        if (!Directory.Exists(directory))
            return;

        foreach (var file in Directory.EnumerateFiles(directory, "*.json"))
        {
            var json = File.ReadAllText(file);
            var raw = JsonSerializer.Deserialize<ItemDefinitionJson>(json, JsonOptions)
                      ?? throw new InvalidOperationException($"Failed to parse item file: {file}");
            if (string.IsNullOrWhiteSpace(raw.Id))
                throw new InvalidOperationException($"Item file missing id: {file}");

            var lootValue = (int)(raw.LootValue ?? raw.Value ?? 1);
            defs[raw.Id] = new ItemDefinition(
                raw.Id,
                raw.Name ?? raw.Id,
                raw.ItemType ?? "material",
                lootValue,
                Path.GetRelativePath(ContentPaths.Root, file).Replace('\\', '/'));
        }
    }

    private sealed record ItemDefinitionJson(
        string Id,
        string? Name,
        string? ItemType,
        double? Value,
        double? LootValue);
}

public sealed record ItemDefinition(
    string Id,
    string Name,
    string ItemType,
    int LootValue,
    string ContentPath);
