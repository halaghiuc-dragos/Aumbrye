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
        ulong x = ((ulong)(uint)tierSeed * 0x9E3779B1UL) ^ ((ulong)(uint)floorIndex * 0xBF58476D1CE4E5B9UL);
        x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9UL;
        x = (x ^ (x >> 27)) * 0x94D049BB133111EBUL;
        x = x ^ (x >> 31);
        return Math.Max(1, (int)(x & 0x7FFFFFFFUL));
    }

    public static int GenerationSeed(int baseSeed, int tier, int floorIndex) =>
        MixFloorSeed(DeriveTierSeed(baseSeed, tier), floorIndex);
}
