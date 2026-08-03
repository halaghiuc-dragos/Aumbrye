namespace Aumbrye.Procedural.Generation;

/// <summary>
/// Maps a player-facing base run seed to per-tier / per-floor generation seeds.
/// Tier 1 uses the base seed; higher tiers derive a distinct but stable seed (Y from X).
/// </summary>
public static class DungeonSeedDeriver
{
    public const int TierSeedMultiplier = 104_729;
    public const int FloorSeedMultiplier = 7_919;

    public static int DeriveTierSeed(int baseSeed, int tier)
    {
        baseSeed = Math.Max(1, baseSeed);
        tier = Math.Clamp(tier, 1, 10);
        if (tier <= 1)
            return baseSeed;
        var mixed = unchecked(baseSeed ^ (tier * TierSeedMultiplier));
        return Math.Max(1, mixed);
    }

    public static int MixFloorSeed(int tierSeed, int floorIndex)
    {
        tierSeed = Math.Max(1, tierSeed);
        floorIndex = Math.Max(1, floorIndex);
        if (floorIndex <= 1)
            return tierSeed;
        return Math.Max(1, unchecked(tierSeed + floorIndex * FloorSeedMultiplier));
    }

    public static int GenerationSeed(int baseSeed, int tier, int floorIndex) =>
        MixFloorSeed(DeriveTierSeed(baseSeed, tier), floorIndex);
}
