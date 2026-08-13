using System.Text.Json;

namespace Aumbrye.Procedural.Content;

/// <summary>
/// The set of recipe ids the game ships. Only identity is needed here — the crafting rules
/// themselves live client-side; the backend just has to reject ids that do not exist.
/// </summary>
public static class RecipeCatalog
{
    private static readonly Lazy<HashSet<string>> Ids = new(LoadIds);

    public static IReadOnlySet<string> AllIds => Ids.Value;

    public static bool Contains(string recipeId) => Ids.Value.Contains(recipeId);

    private static HashSet<string> LoadIds()
    {
        var ids = new HashSet<string>(StringComparer.Ordinal);
        var directory = Path.Combine(ContentPaths.Root, "recipes");
        if (!Directory.Exists(directory))
            return ids;

        foreach (var file in Directory.EnumerateFiles(directory, "*.json"))
        {
            try
            {
                using var document = JsonDocument.Parse(File.ReadAllText(file));
                if (document.RootElement.TryGetProperty("id", out var idElement)
                    && idElement.ValueKind == JsonValueKind.String)
                {
                    var id = idElement.GetString();
                    if (!string.IsNullOrWhiteSpace(id))
                        ids.Add(id);
                }
            }
            catch (JsonException)
            {
                // A malformed recipe file is a content-validation problem, not a reason to fail
                // every save write that happens to mention a recipe.
            }
        }

        return ids;
    }
}
