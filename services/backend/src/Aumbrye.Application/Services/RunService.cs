using System.Security.Cryptography;
using Aumbrye.Application.Abstractions;
using Aumbrye.Domain.Entities;
using Aumbrye.Procedural.Biome;
using Aumbrye.Procedural.Generation;
using Microsoft.EntityFrameworkCore;

namespace Aumbrye.Application.Services;

public class RunService : IRunService
{
    private readonly DbContext _db;
    private readonly IDungeonGenerator _generator;
    private readonly IDungeonCache _cache;
    private static readonly TimeSpan CacheTtl = TimeSpan.FromHours(24);

    public RunService(DbContext db, IDungeonGenerator generator, IDungeonCache cache)
    {
        _db = db;
        _generator = generator;
        _cache = cache;
    }

    public async Task<CreateRunResult> CreateRunAsync(
        Guid accountId,
        string biomeId,
        int? seed,
        int tier,
        CancellationToken ct = default)
    {
        var account = await _db.Set<Account>().FirstOrDefaultAsync(a => a.Id == accountId, ct);
        if (account == null)
            return new CreateRunResult(false, Error: "Account not found.");

        if (!BiomeCatalog.TryGet(biomeId, out _))
            return new CreateRunResult(false, Error: $"Unknown biome '{biomeId}'.");

        if (tier < 1 || tier > 10)
            return new CreateRunResult(false, Error: "Tier must be between 1 and 10.");

        if (seed is < 1)
            return new CreateRunResult(false, Error: "Seed must be at least 1.");

        var actualSeed = seed ?? RandomNumberGenerator.GetInt32(1, int.MaxValue);
        var runId = Guid.NewGuid();
        var playerLevel = 1;

        string json;
        string? checksum;
        try
        {
            (json, checksum) = _generator.Generate(biomeId, actualSeed, tier, playerLevel, runId);
        }
        catch (Exception ex)
        {
            return new CreateRunResult(false, Error: ex.Message);
        }

        var run = new Run
        {
            Id = runId,
            AccountId = accountId,
            BiomeId = biomeId,
            Seed = actualSeed,
            Tier = tier,
            PlayerLevelSnapshot = playerLevel,
            Status = RunStatus.Active,
            CreatedAt = DateTimeOffset.UtcNow,
            DefinitionChecksum = checksum,
        };
        _db.Set<Run>().Add(run);
        await _db.SaveChangesAsync(ct);
        await _cache.SetAsync(runId, json, CacheTtl, ct);

        return new CreateRunResult(true, runId, actualSeed, biomeId, json);
    }

    public async Task<string?> GetDungeonDefinitionAsync(Guid accountId, Guid runId, CancellationToken ct = default)
    {
        var run = await _db.Set<Run>()
            .FirstOrDefaultAsync(r => r.Id == runId && r.AccountId == accountId, ct);
        if (run == null)
            return null;

        var cached = await _cache.GetAsync(runId, ct);
        if (cached != null)
            return cached;

        var (json, _) = _generator.Generate(
            run.BiomeId,
            run.Seed,
            run.Tier,
            run.PlayerLevelSnapshot,
            run.Id);
        await _cache.SetAsync(runId, json, CacheTtl, ct);
        return json;
    }

    public async Task<CompleteRunResult> CompleteRunAsync(
        Guid accountId,
        Guid runId,
        CompleteRunInput input,
        CancellationToken ct = default)
    {
        var run = await _db.Set<Run>()
            .FirstOrDefaultAsync(r => r.Id == runId && r.AccountId == accountId, ct);
        if (run == null)
            return new CompleteRunResult(false, Error: "Run not found.");
        if (run.Status == RunStatus.Completed)
            return new CompleteRunResult(false, runId, Error: "Run already completed.");

        if (input.Outcome is not ("escaped" or "died" or "abandoned"))
            return new CompleteRunResult(false, runId, Error: "Invalid outcome.");

        if (input.Outcome == "escaped" && !input.BossDefeated)
            return new CompleteRunResult(false, runId, Error: "Boss must be defeated to escape.");

        if (input.ElapsedSeconds < 0 || input.ElapsedSeconds > 86_400)
            return new CompleteRunResult(false, runId, Error: "Invalid elapsed time.");

        foreach (var lootId in input.LootClaimedInstanceIds)
        {
            if (string.IsNullOrWhiteSpace(lootId) || !Guid.TryParse(lootId, out _))
                return new CompleteRunResult(false, runId, Error: "Invalid loot instance id.");
        }

        var definitionJson = await _cache.GetAsync(runId, ct);
        if (definitionJson == null)
        {
            (definitionJson, _) = _generator.Generate(
                run.BiomeId,
                run.Seed,
                run.Tier,
                run.PlayerLevelSnapshot,
                run.Id);
        }

        var validLootIds = LootInstanceIds.FromDefinitionJson(definitionJson);
        foreach (var lootId in input.LootClaimedInstanceIds)
        {
            if (!validLootIds.Contains(lootId))
                return new CompleteRunResult(false, runId, Error: "Unknown loot instance id.");
        }

        run.Status = RunStatus.Completed;
        run.CompletedAt = DateTimeOffset.UtcNow;
        await _db.SaveChangesAsync(ct);
        return new CompleteRunResult(true, runId, "completed");
    }
}

public class ProceduralDungeonGenerator : IDungeonGenerator
{
    public (string Json, string? Checksum) Generate(
        string biomeId,
        int seed,
        int tier,
        int playerLevel,
        Guid runId)
    {
        var result = DungeonGenerator.Generate(biomeId, seed, tier, playerLevel, runId);
        return (result.Json, result.Definition.Checksum);
    }
}
