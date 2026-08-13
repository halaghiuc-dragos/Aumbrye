namespace Aumbrye.Procedural.Random;

/// <summary>
/// Deterministic PRNG (SplitMix64). Same seed produces identical sequences on all platforms.
/// </summary>
/// <remarks>
/// <para><b>Frozen cross-language contract.</b> The GDScript twin must produce bit-identical
/// sequences, so nothing here may change unilaterally — including the range reduction.</para>
/// <para><see cref="NextInt(int)"/> reduces with plain modulo, which is biased for ranges that do
/// not divide 2^64 evenly. The bias is negligible at gameplay range sizes (below one part in 2^40
/// for any range under a million) and is <i>intentional and contractually frozen</i> rather than
/// an oversight: it is the simplest reduction to reimplement identically in another language, and
/// the golden sequences in SeedReproducibilityTests pin it. Switching to Lemire multiply-shift
/// would be a real improvement, but only as a coordinated change landing in both languages in the
/// same release with regenerated goldens.</para>
/// </remarks>
public sealed class SeededRandom
{
    private ulong _state;

    public SeededRandom(int seed)
    {
        _state = (ulong)(uint)seed;
        if (_state == 0)
            _state = 0x9E3779B97F4A7C15UL;
    }

    /// <summary>Draws in [0, maxExclusive). See the type remarks on the frozen modulo reduction.</summary>
    public int NextInt(int maxExclusive)
    {
        ArgumentOutOfRangeException.ThrowIfLessThanOrEqual(maxExclusive, 0);
        return (int)(NextULong() % (ulong)maxExclusive);
    }

    /// <summary>Draws in [minInclusive, maxExclusive). See the type remarks on the frozen modulo reduction.</summary>
    public int NextInt(int minInclusive, int maxExclusive)
    {
        ArgumentOutOfRangeException.ThrowIfLessThanOrEqual(maxExclusive, minInclusive);
        var range = (ulong)(maxExclusive - minInclusive);
        return minInclusive + (int)(NextULong() % range);
    }

    public void Shuffle<T>(IList<T> list)
    {
        for (var i = list.Count - 1; i > 0; i--)
        {
            var j = NextInt(i + 1);
            (list[i], list[j]) = (list[j], list[i]);
        }
    }

    private ulong NextULong()
    {
        _state += 0x9E3779B97F4A7C15UL;
        var z = _state;
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
        return z ^ (z >> 31);
    }
}
