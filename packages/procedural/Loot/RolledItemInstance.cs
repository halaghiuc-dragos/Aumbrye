namespace Aumbrye.Procedural.Loot;

public sealed record RolledAffix(string AffixId, double Value);

public sealed record RolledItemInstance(
    int SchemaVersion,
    string InstanceId,
    string ItemDefId,
    string Rarity,
    IReadOnlyList<RolledAffix> Affixes,
    int RollSeed,
    double Durability = 100,
    bool Bound = false);

public static class ItemRarities
{
    public const string Common = "common";
    public const string Magic = "magic";
    public const string Rare = "rare";
    public const string Epic = "epic";
    public const string Legendary = "legendary";
    public const string Mythic = "mythic";

    public static readonly string[] All =
    [
        Common, Magic, Rare, Epic, Legendary, Mythic,
    ];
}
