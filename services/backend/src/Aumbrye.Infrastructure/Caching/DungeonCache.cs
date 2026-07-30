using System.Collections.Concurrent;
using Aumbrye.Application.Abstractions;
using StackExchange.Redis;

namespace Aumbrye.Infrastructure.Caching;

public class RedisDungeonCache : IDungeonCache
{
    private readonly IConnectionMultiplexer? _redis;
    private readonly ConcurrentDictionary<Guid, (string Json, DateTimeOffset Expires)> _fallback = new();

    public RedisDungeonCache(IConnectionMultiplexer? redis = null) => _redis = redis;

    public async Task SetAsync(Guid runId, string definitionJson, TimeSpan ttl, CancellationToken ct = default)
    {
        if (_redis != null)
        {
            try
            {
                var db = _redis.GetDatabase();
                await db.StringSetAsync(CacheKey(runId), definitionJson, ttl);
                return;
            }
            catch (RedisException)
            {
                // Fall through to in-memory when Redis is unavailable.
            }
        }
        _fallback[runId] = (definitionJson, DateTimeOffset.UtcNow.Add(ttl));
        await Task.CompletedTask;
    }

    public async Task<string?> GetAsync(Guid runId, CancellationToken ct = default)
    {
        if (_redis != null)
        {
            try
            {
                var db = _redis.GetDatabase();
                var value = await db.StringGetAsync(CacheKey(runId));
                if (value.HasValue)
                    return value.ToString();
            }
            catch (RedisException)
            {
                // Fall through to in-memory fallback.
            }
        }
        if (_fallback.TryGetValue(runId, out var entry) && entry.Expires > DateTimeOffset.UtcNow)
            return entry.Json;
        return null;
    }

    private static string CacheKey(Guid runId) => $"dungeon:{runId:N}";
}

public class InMemoryDungeonCache : IDungeonCache
{
    private readonly ConcurrentDictionary<Guid, (string Json, DateTimeOffset Expires)> _store = new();

    public Task SetAsync(Guid runId, string definitionJson, TimeSpan ttl, CancellationToken ct = default)
    {
        _store[runId] = (definitionJson, DateTimeOffset.UtcNow.Add(ttl));
        return Task.CompletedTask;
    }

    public Task<string?> GetAsync(Guid runId, CancellationToken ct = default)
    {
        if (_store.TryGetValue(runId, out var entry) && entry.Expires > DateTimeOffset.UtcNow)
            return Task.FromResult<string?>(entry.Json);
        return Task.FromResult<string?>(null);
    }
}
