using System.Text.Json.Nodes;
using Aumbrye.Procedural.Content;
using Aumbrye.Procedural.Loot;

namespace Aumbrye.Application.Services;

/// <summary>
/// Server-side invariants over a client-supplied save blob.
/// </summary>
/// <remarks>
/// The save endpoint previously validated talents and accepted everything else verbatim, so a
/// crafted request could declare max level and fabricated legendary equipment — which then fed
/// <c>PlayerLevelSnapshot</c> into dungeon generation and inflated loot budgets. The decisive
/// check is <see cref="ValidateItemInstances"/>: affix rolls are a pure function of
/// (instanceId, itemDefId, rollSeed), so the server can re-derive every item the client claims to
/// own and reject any that does not match.
/// </remarks>
public static class SaveStateValidator
{
    /// <summary>Largest accepted save body. Comfortably above a full inventory, far below a DoS.</summary>
    public const int MaxStateJsonBytes = 256 * 1024;

    private const long MaxGold = 100_000_000L;
    private const int MaxInventorySlots = 4096;
    private const int MaxItemInstances = 4096;

    /// <summary>Returns the first violation found, or null when the state is acceptable.</summary>
    public static string? Validate(JsonObject state)
    {
        return ValidateCharacter(state)
               ?? ValidateCurrencies(state)
               ?? ValidateInventory(state)
               ?? ValidateItemInstances(state)
               ?? ValidateRecipes(state)
               ?? TalentValidator.ValidateTalents(state);
    }

    private static string? ValidateCharacter(JsonObject state)
    {
        if (state["character"] is not JsonObject character)
            return "Save is missing 'character'.";

        var curve = ProgressionCatalog.XpCurve;

        if (!TryGetInt(character["level"], out var level))
            return "character.level must be an integer.";
        if (level < 1 || level > curve.MaxLevel)
            return $"character.level must be between 1 and {curve.MaxLevel}.";

        if (!TryGetInt(character["xp"], out var xp))
            return "character.xp must be an integer.";
        if (xp < 0)
            return "character.xp cannot be negative.";

        // Level is derived from XP, so a mismatch means one of the two was hand-edited.
        var expectedLevel = curve.LevelForXp(xp);
        if (level != expectedLevel)
            return $"character.level {level} does not match {xp} xp (expected {expectedLevel}).";

        return null;
    }

    private static string? ValidateCurrencies(JsonObject state)
    {
        if (state["currencies"] is not JsonObject currencies)
            return null;

        foreach (var (name, valueNode) in currencies)
        {
            if (!TryGetLong(valueNode, out var amount))
                return $"currencies.{name} must be an integer.";
            if (amount < 0 || amount > MaxGold)
                return $"currencies.{name} must be between 0 and {MaxGold}.";
        }

        return null;
    }

    private static string? ValidateInventory(JsonObject state)
    {
        if (state["inventory"] is not JsonObject inventory)
            return null;

        var width = TryGetInt(inventory["gridWidth"], out var w) ? w : 6;
        var height = TryGetInt(inventory["gridHeight"], out var h) ? h : 4;
        if (width is < 1 or > 64 || height is < 1 or > 64)
            return "inventory grid dimensions are out of range.";

        if (inventory["slots"] is not JsonArray slots)
            return null;
        if (slots.Count > MaxInventorySlots)
            return $"inventory holds more than {MaxInventorySlots} slots.";

        var occupied = new HashSet<(int X, int Y)>();
        foreach (var slotNode in slots)
        {
            if (slotNode is not JsonObject slot)
                return "inventory.slots entries must be objects.";

            var itemId = slot["itemId"]?.GetValue<string>();
            if (string.IsNullOrWhiteSpace(itemId))
                return "inventory slot is missing itemId.";
            if (!ItemCatalog.TryGet(itemId, out _))
                return $"Unknown item '{itemId}' in inventory.";

            if (!TryGetInt(slot["quantity"], out var quantity) || quantity < 1)
                return $"inventory slot for '{itemId}' has an invalid quantity.";

            if (!TryGetInt(slot["x"], out var x) || !TryGetInt(slot["y"], out var y))
                return $"inventory slot for '{itemId}' is missing coordinates.";
            if (x < 0 || y < 0 || x >= width || y >= height)
                return $"inventory slot for '{itemId}' is outside the {width}x{height} grid.";
            if (!occupied.Add((x, y)))
                return $"inventory has two items stacked at ({x}, {y}).";
        }

        return null;
    }

    private static string? ValidateItemInstances(JsonObject state)
    {
        if (state["itemInstances"] is not JsonObject instances)
            return null;
        if (instances.Count > MaxItemInstances)
            return $"Save declares more than {MaxItemInstances} item instances.";

        foreach (var (instanceId, instanceNode) in instances)
        {
            if (instanceNode is not JsonObject instance)
                return $"itemInstances['{instanceId}'] must be an object.";

            var itemDefId = instance["itemDefId"]?.GetValue<string>();
            if (string.IsNullOrWhiteSpace(itemDefId))
                return $"itemInstances['{instanceId}'] is missing itemDefId.";
            if (!ItemCatalog.TryGet(itemDefId, out _))
                return $"itemInstances['{instanceId}'] references unknown item '{itemDefId}'.";

            if (!TryGetInt(instance["rollSeed"], out var rollSeed))
                return $"itemInstances['{instanceId}'] is missing rollSeed.";

            RolledItemInstance expected;
            try
            {
                expected = AffixRoller.RollWithSeed(instanceId, itemDefId, rollSeed);
            }
            catch (ArgumentException)
            {
                return $"itemInstances['{instanceId}'] cannot be re-rolled.";
            }

            var claimedRarity = instance["rarity"]?.GetValue<string>();
            if (!string.Equals(claimedRarity, expected.Rarity, StringComparison.Ordinal))
                return $"itemInstances['{instanceId}'] claims rarity '{claimedRarity}' but rolls '{expected.Rarity}'.";

            var affixError = ValidateAffixes(instanceId, instance["affixes"] as JsonArray, expected);
            if (affixError != null)
                return affixError;
        }

        return null;
    }

    private static string? ValidateAffixes(string instanceId, JsonArray? claimed, RolledItemInstance expected)
    {
        var claimedCount = claimed?.Count ?? 0;
        if (claimedCount != expected.Affixes.Count)
        {
            return $"itemInstances['{instanceId}'] claims {claimedCount} affixes but rolls "
                   + $"{expected.Affixes.Count}.";
        }

        for (var i = 0; i < expected.Affixes.Count; i++)
        {
            if (claimed![i] is not JsonObject affix)
                return $"itemInstances['{instanceId}'] affix {i} must be an object.";

            var affixId = affix["affixId"]?.GetValue<string>();
            if (!string.Equals(affixId, expected.Affixes[i].AffixId, StringComparison.Ordinal))
            {
                return $"itemInstances['{instanceId}'] affix {i} is '{affixId}' but rolls "
                       + $"'{expected.Affixes[i].AffixId}'.";
            }

            if (!TryGetDouble(affix["value"], out var value))
                return $"itemInstances['{instanceId}'] affix {i} has a non-numeric value.";

            // Rolls are deterministic doubles; only floating-point round-tripping should differ.
            if (Math.Abs(value - expected.Affixes[i].Value) > 1e-6)
            {
                return $"itemInstances['{instanceId}'] affix '{affixId}' claims {value} but rolls "
                       + $"{expected.Affixes[i].Value}.";
            }
        }

        return null;
    }

    private static string? ValidateRecipes(JsonObject state)
    {
        if (state["recipes"] is not JsonArray recipes)
            return null;

        // An empty catalog means the content directory was not shipped alongside the API; skipping
        // is safer than rejecting every save.
        if (RecipeCatalog.AllIds.Count == 0)
            return null;

        foreach (var recipeNode in recipes)
        {
            var recipeId = recipeNode?.GetValue<string>();
            if (string.IsNullOrWhiteSpace(recipeId))
                return "recipes contains an empty entry.";
            if (!RecipeCatalog.Contains(recipeId))
                return $"Unknown recipe '{recipeId}'.";
        }

        return null;
    }

    private static bool TryGetInt(JsonNode? node, out int value)
    {
        value = 0;
        return node != null && node.AsValue().TryGetValue(out value);
    }

    private static bool TryGetLong(JsonNode? node, out long value)
    {
        value = 0;
        return node != null && node.AsValue().TryGetValue(out value);
    }

    private static bool TryGetDouble(JsonNode? node, out double value)
    {
        value = 0;
        return node != null && node.AsValue().TryGetValue(out value);
    }
}
