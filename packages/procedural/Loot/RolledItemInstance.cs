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

    /// <summary>Top rarity. Content and the client's RarityRegistry both call this "aumbral".</summary>
    public const string Aumbral = "aumbral";

    /// <summary>
    /// Former name of <see cref="Aumbral"/>. Still present in saves written before the rename, so
    /// it must be normalized on read — never rolled.
    /// </summary>
    public const string LegacyMythic = "mythic";

    public static readonly string[] All =
    [
        Common, Magic, Rare, Epic, Legendary, Aumbral,
    ];

    /// <summary>Maps a stored rarity onto its canonical name, mirroring RarityRegistry.normalize().</summary>
    public static string Normalize(string rarity) =>
        string.Equals(rarity, LegacyMythic, StringComparison.OrdinalIgnoreCase) ? Aumbral : rarity;
}
