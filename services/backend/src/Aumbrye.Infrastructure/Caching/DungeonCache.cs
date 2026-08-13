using Aumbrye.Application.Abstractions;
using Microsoft.Extensions.Caching.Memory;
using StackExchange.Redis;

namespace Aumbrye.Infrastructure.Caching;

/// <summary>
/// Bounded in-process store for dungeon definitions.
/// </summary>
/// <remarks>
/// Entries are multi-KB JSON strings, one per run per floor. A hand-rolled dictionary that only
/// checked expiry on read never physically removed anything, so a Redis outage (or simply running
/// without Redis) grew the process heap without bound for its whole lifetime. MemoryCache handles
/// expiration scanning and size-based compaction natively; the size unit here is characters, so
/// the limit is roughly 2× that many bytes of UTF-16 payload.
/// </remarks>
internal sealed class BoundedDefinitionCache : IDisposable
{
    /// <summary>~128M chars ≈ 256 MB of definition payload before compaction kicks in.</summary>
    public const long DefaultSizeLimit = 128L * 1024 * 1024;

    private readonly MemoryCache _cache;

    public BoundedDefinitionCache(long sizeLimit = DefaultSizeLimit) =>
        _cache = new MemoryCache(new MemoryCacheOptions { SizeLimit = sizeLimit });

    public void Set(Guid runId, int floor, string definitionJson, TimeSpan ttl)
    {
        // A non-positive TTL means "already expired". MemoryCache rejects it outright, so evict
        // instead — the observable result (a subsequent Get misses) is the same.
        if (ttl <= TimeSpan.Zero)
        {
            _cache.Remove(CacheKey(runId, floor));
            return;
        }

        _cache.Set(
            CacheKey(runId, floor),
            definitionJson,
            new MemoryCacheEntryOptions
            {
                AbsoluteExpirationRelativeToNow = ttl,
                // Never let a single definition be worth less than one unit, or a degenerate empty
                // payload would be uncountable against the limit.
                Size = Math.Max(1, definitionJson.Length),
            });
    }

    public string? Get(Guid runId, int floor) =>
        _cache.TryGetValue(CacheKey(runId, floor), out string? json) ? json : null;

    public void Dispose() => _cache.Dispose();

    private static string CacheKey(Guid runId, int floor) => $"dungeon:{runId:N}:{floor}";
}

public class RedisDungeonCache : IDungeonCache, IDisposable
{
    private readonly IConnectionMultiplexer? _redis;
    private readonly BoundedDefinitionCache _fallback = new();

    public RedisDungeonCache(IConnectionMultiplexer? redis = null) => _redis = redis;

    public async Task SetAsync(Guid runId, int floor, string definitionJson, TimeSpan ttl, CancellationToken ct = default)
    {
        if (_redis != null)
        {
            try
            {
                var db = _redis.GetDatabase();
                await db.StringSetAsync(CacheKey(runId, floor), definitionJson, ttl);
                return;
            }
            catch (RedisException)
            {
                // Fall through to in-memory when Redis is unavailable.
            }
        }

        _fallback.Set(runId, floor, definitionJson, ttl);
    }

    public async Task<string?> GetAsync(Guid runId, int floor, CancellationToken ct = default)
    {
        if (_redis != null)
        {
            try
            {
                var db = _redis.GetDatabase();
                var value = await db.StringGetAsync(CacheKey(runId, floor));
                if (value.HasValue)
                    return value.ToString();
            }
            catch (RedisException)
            {
                // Fall through to in-memory fallback.
            }
        }

        return _fallback.Get(runId, floor);
    }

    public void Dispose() => _fallback.Dispose();

    private static string CacheKey(Guid runId, int floor) => $"dungeon:{runId:N}:{floor}";
}

/// <summary>Used whenever Redis is not configured — including in production, so it must be bounded.</summary>
public class InMemoryDungeonCache : IDungeonCache, IDisposable
{
    private readonly BoundedDefinitionCache _store = new();

    public Task SetAsync(Guid runId, int floor, string definitionJson, TimeSpan ttl, CancellationToken ct = default)
    {
        _store.Set(runId, floor, definitionJson, ttl);
        return Task.CompletedTask;
    }

    public Task<string?> GetAsync(Guid runId, int floor, CancellationToken ct = default) =>
        Task.FromResult(_store.Get(runId, floor));

    public void Dispose() => _store.Dispose();
}
