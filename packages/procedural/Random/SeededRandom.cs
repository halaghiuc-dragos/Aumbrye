namespace Aumbrye.Procedural.Random;

/// <summary>
/// Deterministic PRNG (SplitMix64). Same seed produces identical sequences on all platforms.
/// </summary>
public sealed class SeededRandom
{
    private ulong _state;

    public SeededRandom(int seed)
    {
        _state = (ulong)(uint)seed;
        if (_state == 0)
            _state = 0x9E3779B97F4A7C15UL;
    }

    public int NextInt(int maxExclusive)
    {
        ArgumentOutOfRangeException.ThrowIfLessThanOrEqual(maxExclusive, 0);
        return (int)(NextULong() % (ulong)maxExclusive);
    }

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
