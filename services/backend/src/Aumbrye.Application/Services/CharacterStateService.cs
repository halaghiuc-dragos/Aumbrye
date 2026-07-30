using System.Text.Json;
using System.Text.Json.Nodes;
using Aumbrye.Application.Abstractions;
using Aumbrye.Procedural.Content;
using Aumbrye.Procedural.Loot;

namespace Aumbrye.Application.Services;

public static class CharacterStateDefaults
{
    public static JsonObject Create(Guid accountId) => new()
    {
        ["schemaVersion"] = 1,
        ["accountId"] = accountId.ToString(),
        ["character"] = new JsonObject
        {
            ["name"] = "Wanderer",
            ["level"] = 1,
            ["xp"] = 0,
            ["lastHubMessage"] = "",
            ["firstPersonCamera"] = false,
        },
        ["currencies"] = new JsonObject { ["gold"] = 0 },
        ["inventory"] = new JsonObject
        {
            ["schemaVersion"] = 1,
            ["gridWidth"] = 6,
            ["gridHeight"] = 4,
            ["slots"] = new JsonArray
            {
                new JsonObject
                {
                    ["itemId"] = "castle_sword",
                    ["quantity"] = 1,
                    ["x"] = 0,
                    ["y"] = 0,
                },
            },
            ["equipped"] = new JsonObject { ["weapon"] = "castle_sword" },
        },
        ["itemInstances"] = new JsonObject(),
        ["talents"] = new JsonObject(),
        ["flags"] = new JsonObject(),
        ["recipes"] = new JsonArray(),
        ["runRelics"] = new JsonArray(),
    };
}

public static class TalentValidator
{
    public static string? ValidateTalents(JsonObject state)
    {
        var tree = TalentCatalog.GetTree();
        var character = state["character"] as JsonObject;
        var level = character?["level"]?.GetValue<int>() ?? 1;
        var maxPoints = ProgressionCatalog.XpCurve.TalentPointsForLevel(level, tree.TalentPointsPerLevel);

        var talents = state["talents"] as JsonObject ?? new JsonObject();
        var totalSpent = 0;
        foreach (var (nodeId, rankNode) in talents)
        {
            if (!tree.TryGetNode(nodeId, out var node) || node is null)
                return $"Unknown talent node '{nodeId}'.";

            var rank = rankNode?.GetValue<int>() ?? 0;
            if (rank < 0)
                return $"Negative rank for talent '{nodeId}'.";
            if (rank > node.MaxRank)
                return $"Talent '{nodeId}' exceeds max rank {node.MaxRank}.";

            totalSpent += rank * node.CostPerRank;
            foreach (var req in node.Requires)
            {
                var reqRank = talents[req]?.GetValue<int>() ?? 0;
                if (reqRank < 1)
                    return $"Talent '{nodeId}' requires '{req}' to be unlocked.";
            }
        }

        if (totalSpent > maxPoints)
            return $"Spent {totalSpent} talent points but only {maxPoints} available at level {level}.";

        return null;
    }
}

public static class ProgressionApplier
{
    public static RunProgressionResult ApplyRunOutcome(
        JsonObject state,
        string outcome,
        int tier,
        IReadOnlyList<string> lootClaimedInstanceIds,
        IReadOnlyDictionary<string, LootInstanceIds.LootEntry> lootMap)
    {
        var curve = ProgressionCatalog.XpCurve;
        var runXp = curve.BaseXpPerRun + Math.Max(0, tier - 1) * curve.TierXpBonus;
        var xpFraction = outcome switch
        {
            "escaped" => 1.0,
            "died" => curve.DeathXpFraction,
            "abandoned" => curve.AbandonedXpFraction,
            _ => 0,
        };
        var xpGained = (int)Math.Round(runXp * xpFraction);

        var character = state["character"] as JsonObject ?? new JsonObject();
        var previousLevel = character["level"]?.GetValue<int>() ?? 1;
        var previousXp = character["xp"]?.GetValue<int>() ?? 0;
        var newXp = previousXp + xpGained;
        var newLevel = curve.LevelForXp(newXp);
        character["xp"] = newXp;
        character["level"] = newLevel;
        state["character"] = character;

        var lootGranted = new List<JsonObject>();
        if (outcome == "escaped")
        {
            foreach (var instanceId in lootClaimedInstanceIds)
            {
                if (!lootMap.TryGetValue(instanceId, out var entry))
                    continue;
                GrantLoot(state, instanceId, entry.ItemId, entry.Quantity, lootGranted);
            }
        }

        ClearRunState(state, stripRelics: outcome is "died" or "abandoned");

        var tree = TalentCatalog.GetTree();
        var talentPointsEarned = Math.Max(0, newLevel - previousLevel) * tree.TalentPointsPerLevel;
        var economyNote = outcome switch
        {
            "escaped" => "Escaped: kept loot, full XP.",
            "died" => $"Died: {curve.DeathXpFraction:P0} XP, run relics lost, unextracted loot lost.",
            "abandoned" => "Abandoned: no XP or loot.",
            _ => "",
        };

        return new RunProgressionResult(
            xpGained,
            newXp,
            newLevel,
            talentPointsEarned,
            lootGranted,
            economyNote);
    }

    private static void GrantLoot(
        JsonObject state,
        string instanceId,
        string itemId,
        int quantity,
        List<JsonObject> lootGranted)
    {
        if (AffixRoller.IsEquipment(itemId))
        {
            var rolled = AffixRoller.Roll(instanceId, itemId);
            var instances = state["itemInstances"] as JsonObject ?? new JsonObject();
            instances[instanceId] = JsonNode.Parse(AffixRoller.ToJsonElement(rolled).GetRawText())!.AsObject();
            state["itemInstances"] = instances;

            var inventory = state["inventory"] as JsonObject ?? new JsonObject();
            var slots = inventory["slots"] as JsonArray ?? new JsonArray();
            var (x, y) = FindNextSlot(inventory);
            slots.Add(new JsonObject
            {
                ["instanceId"] = instanceId,
                ["itemId"] = itemId,
                ["quantity"] = 1,
                ["x"] = x,
                ["y"] = y,
            });
            inventory["slots"] = slots;
            state["inventory"] = inventory;

            lootGranted.Add(new JsonObject
            {
                ["instanceId"] = instanceId,
                ["itemDefId"] = itemId,
                ["rarity"] = rolled.Rarity,
                ["affixCount"] = rolled.Affixes.Count,
            });
            return;
        }

        AddStackable(state, itemId, quantity);
        lootGranted.Add(new JsonObject
        {
            ["itemId"] = itemId,
            ["quantity"] = quantity,
        });
    }

    private static void AddStackable(JsonObject state, string itemId, int quantity)
    {
        var inventory = state["inventory"] as JsonObject ?? new JsonObject();
        var slots = inventory["slots"] as JsonArray ?? new JsonArray();
        foreach (var slotNode in slots)
        {
            if (slotNode is not JsonObject slot)
                continue;
            if (slot["itemId"]?.GetValue<string>() == itemId
                && !slot.ContainsKey("instanceId"))
            {
                slot["quantity"] = (slot["quantity"]?.GetValue<int>() ?? 0) + quantity;
                inventory["slots"] = slots;
                state["inventory"] = inventory;
                return;
            }
        }

        var (x, y) = FindNextSlot(inventory);
        slots.Add(new JsonObject
        {
            ["itemId"] = itemId,
            ["quantity"] = quantity,
            ["x"] = x,
            ["y"] = y,
        });
        inventory["slots"] = slots;
        state["inventory"] = inventory;
    }

    private static (int X, int Y) FindNextSlot(JsonObject inventory)
    {
        var width = inventory["gridWidth"]?.GetValue<int>() ?? 6;
        var height = inventory["gridHeight"]?.GetValue<int>() ?? 4;
        var occupied = new HashSet<(int, int)>();
        if (inventory["slots"] is JsonArray slots)
        {
            foreach (var slotNode in slots)
            {
                if (slotNode is JsonObject slot)
                {
                    var sx = slot["x"]?.GetValue<int>() ?? -1;
                    var sy = slot["y"]?.GetValue<int>() ?? -1;
                    if (sx >= 0 && sy >= 0)
                        occupied.Add((sx, sy));
                }
            }
        }

        for (var y = 0; y < height; y++)
        for (var x = 0; x < width; x++)
        {
            if (!occupied.Contains((x, y)))
                return (x, y);
        }

        return (0, height);
    }

    private static void ClearRunState(JsonObject state, bool stripRelics)
    {
        state.Remove("activeRun");
        if (stripRelics)
            state["runRelics"] = new JsonArray();
    }
}
