using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Aumbrye.Procedural.Content;
using Aumbrye.Procedural.Loot;
using Aumbrye.Procedural.Random;

namespace Aumbrye.Procedural.Loot;

/// <summary>
/// LOOT-4.1 — deterministic affix roller. Same rollSeed + itemDefId → identical affixes.
/// </summary>
public static class AffixRoller
{
    public static int DeriveRollSeed(string instanceId)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(instanceId));
        return BitConverter.ToInt32(hash, 0) & int.MaxValue;
    }

    public static RolledItemInstance Roll(string instanceId, string itemDefId)
    {
        var rollSeed = DeriveRollSeed(instanceId);
        return RollWithSeed(instanceId, itemDefId, rollSeed);
    }

    public static RolledItemInstance RollWithSeed(string instanceId, string itemDefId, int rollSeed)
    {
        if (!ItemCatalog.TryGet(itemDefId, out var item))
            throw new ArgumentException($"Unknown item id: {itemDefId}", nameof(itemDefId));

        var itemType = MapItemType(item!.ItemType);
        var rng = new SeededRandom(rollSeed);
        var rarity = RollRarity(rng);
        var affixCount = RollAffixCount(rarity, rng);
        var affixes = PickAffixes(itemType, rarity, affixCount, rng);

        return new RolledItemInstance(
            SchemaVersion: 1,
            InstanceId: instanceId,
            ItemDefId: itemDefId,
            Rarity: rarity,
            Affixes: affixes,
            RollSeed: rollSeed);
    }

    public static bool IsEquipment(string itemDefId) =>
        ItemCatalog.TryGet(itemDefId, out var item)
        && item is not null
        && item.ItemType is "weapon" or "armor" or "accessory";

    private static string MapItemType(string itemType) =>
        itemType switch
        {
            "armor" => "armor",
            "accessory" => "armor",
            _ => "weapon",
        };

    private static string RollRarity(SeededRandom rng)
    {
        var rules = AffixCatalog.RarityRules;
        var total = ItemRarities.All.Sum(r => rules.RarityWeights.GetValueOrDefault(r, 0));
        if (total <= 0)
            return ItemRarities.Common;

        var roll = rng.NextInt(total);
        var cumulative = 0;
        foreach (var rarity in ItemRarities.All)
        {
            cumulative += rules.RarityWeights.GetValueOrDefault(rarity, 0);
            if (roll < cumulative)
                return rarity;
        }

        return ItemRarities.Common;
    }

    private static int RollAffixCount(string rarity, SeededRandom rng)
    {
        if (!AffixCatalog.RarityRules.AffixCounts.TryGetValue(rarity, out var range))
            return 0;
        if (range.Max <= range.Min)
            return range.Min;
        return rng.NextInt(range.Min, range.Max + 1);
    }

    private static List<RolledAffix> PickAffixes(
        string itemType,
        string rarity,
        int affixCount,
        SeededRandom rng)
    {
        if (affixCount <= 0)
            return [];

        var pool = AffixCatalog.AllAffixes
            .Where(a => a.ItemTypes.Contains(itemType))
            .ToList();
        if (pool.Count == 0)
            return [];

        var picked = new List<RolledAffix>();
        var usedIds = new HashSet<string>(StringComparer.Ordinal);
        var working = pool.ToList();

        for (var i = 0; i < affixCount && working.Count > 0; i++)
        {
            var affix = WeightedPick(working, rng);
            if (!usedIds.Add(affix.Id))
            {
                working.RemoveAll(a => a.Id == affix.Id);
                i--;
                continue;
            }

            var value = RollAffixValue(affix, rarity, rng);
            picked.Add(new RolledAffix(affix.Id, value));
            working.RemoveAll(a => a.Id == affix.Id || a.Kind == affix.Kind);
        }

        return picked;
    }

    private static AffixDefinition WeightedPick(IReadOnlyList<AffixDefinition> pool, SeededRandom rng)
    {
        var total = pool.Sum(a => a.Weight);
        var roll = rng.NextInt(total);
        var cumulative = 0;
        foreach (var affix in pool)
        {
            cumulative += affix.Weight;
            if (roll < cumulative)
                return affix;
        }

        return pool[^1];
    }

    private static double RollAffixValue(AffixDefinition affix, string rarity, SeededRandom rng)
    {
        if (!affix.Tiers.TryGetValue(rarity, out var tier))
            return 0;
        if (tier.Max <= tier.Min)
            return tier.Min;

        var isFraction = tier.Max <= 1.0 && tier.Min >= 0 && tier.Max < 10;
        if (isFraction)
        {
            var span = tier.Max - tier.Min;
            return tier.Min + span * (rng.NextInt(10_000) / 10_000.0);
        }

        return rng.NextInt((int)Math.Floor(tier.Min), (int)Math.Ceiling(tier.Max) + 1);
    }

    public static JsonElement ToJsonElement(RolledItemInstance instance)
    {
        var affixes = instance.Affixes
            .Select(a => new Dictionary<string, object>
            {
                ["affixId"] = a.AffixId,
                ["value"] = a.Value,
            })
            .ToList();

        var dict = new Dictionary<string, object?>
        {
            ["schemaVersion"] = instance.SchemaVersion,
            ["instanceId"] = instance.InstanceId,
            ["itemDefId"] = instance.ItemDefId,
            ["rarity"] = instance.Rarity,
            ["affixes"] = affixes,
            ["durability"] = instance.Durability,
            ["bound"] = instance.Bound,
            ["rollSeed"] = instance.RollSeed,
        };

        return JsonSerializer.SerializeToElement(dict);
    }
}
