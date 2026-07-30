using System.Text.Json;

namespace Aumbrye.Application.Services;

internal static class LootInstanceIds
{
    public static HashSet<string> FromDefinitionJson(string json)
    {
        var ids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        using var doc = JsonDocument.Parse(json);
        if (!doc.RootElement.TryGetProperty("placements", out var placements)
            || !placements.TryGetProperty("loot", out var loot))
            return ids;

        foreach (var chest in loot.EnumerateArray())
        {
            if (!chest.TryGetProperty("items", out var items))
                continue;
            foreach (var item in items.EnumerateArray())
            {
                if (item.TryGetProperty("instanceId", out var instanceId)
                    && instanceId.ValueKind == JsonValueKind.String)
                {
                    var value = instanceId.GetString();
                    if (!string.IsNullOrWhiteSpace(value))
                        ids.Add(value);
                }
            }
        }

        return ids;
    }
}
