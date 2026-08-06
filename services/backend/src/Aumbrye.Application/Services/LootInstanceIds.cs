using System.Text.Json;

namespace Aumbrye.Application.Services;

public static class LootInstanceIds
{
    public static HashSet<string> FromDefinitionJson(string json) =>
        ParseLoot(json).Keys.ToHashSet(StringComparer.OrdinalIgnoreCase);

    public static IReadOnlyDictionary<string, LootEntry> ParseLoot(string json)
    {
        var map = new Dictionary<string, LootEntry>(StringComparer.OrdinalIgnoreCase);
        using var doc = JsonDocument.Parse(json);
        if (!doc.RootElement.TryGetProperty("placements", out var placements)
            || !placements.TryGetProperty("loot", out var loot))
            return map;

        foreach (var chest in loot.EnumerateArray())
        {
            if (!chest.TryGetProperty("items", out var items))
                continue;
            foreach (var item in items.EnumerateArray())
            {
                if (!item.TryGetProperty("instanceId", out var instanceId)
                    || instanceId.ValueKind != JsonValueKind.String)
                    continue;
                var id = instanceId.GetString();
                if (string.IsNullOrWhiteSpace(id))
                    continue;

                var itemId = item.TryGetProperty("itemId", out var itemIdEl)
                    ? itemIdEl.GetString() ?? ""
                    : "";
                var quantity = item.TryGetProperty("quantity", out var qtyEl) && qtyEl.TryGetInt32(out var q)
                    ? q
                    : 1;
                map[id] = new LootEntry(itemId, quantity);
            }
        }

        return map;
    }

    public sealed record LootEntry(string ItemId, int Quantity);
}
