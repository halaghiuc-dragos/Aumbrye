using System.Text.Json;
using System.Text.Json.Nodes;
using System.Security.Cryptography;
using Aumbrye.Application.Abstractions;
using Aumbrye.Domain.Entities;
using Aumbrye.Procedural.Biome;
using Aumbrye.Procedural.Generation;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace Aumbrye.Application.Services;

public class RunService : IRunService
{
    private readonly DbContext _db;
    private readonly IDungeonGenerator _generator;
    private readonly IDungeonCache _cache;
    private readonly ILogger<RunService> _logger;
    private static readonly TimeSpan CacheTtl = TimeSpan.FromHours(24);

    public RunService(DbContext db, IDungeonGenerator generator, IDungeonCache cache, ILogger<RunService> logger)
    {
        _db = db;
        _generator = generator;
        _cache = cache;
        _logger = logger;
    }

    private static int GenerationSeedFor(Run run, int floor) =>
        DungeonSeedDeriver.GenerationSeed(run.Seed, run.Tier, floor);

    public async Task<CreateRunResult> CreateRunAsync(
        Guid accountId,
        string biomeId,
        int? seed,
        int tier,
        CancellationToken ct = default)
    {
        var account = await _db.Set<Account>()
            .Include(a => a.SaveBlob)
            .FirstOrDefaultAsync(a => a.Id == accountId, ct);
        if (account == null)
            return new CreateRunResult(false, Error: "Account not found.");

        if (!BiomeCatalog.TryGet(biomeId, out _))
            return new CreateRunResult(false, Error: $"Unknown biome '{biomeId}'.");

        if (tier < 1 || tier > 10)
            return new CreateRunResult(false, Error: "Tier must be between 1 and 10.");

        if (seed is < 1)
            return new CreateRunResult(false, Error: "Seed must be at least 1.");

        var playerLevel = 1;
        if (account.SaveBlob != null)
        {
            var state = SaveService.ParseState(account.SaveBlob.JsonData, accountId);
            playerLevel = state["character"]?["level"]?.GetValue<int>() ?? 1;
        }

        var baseSeed = seed ?? RandomNumberGenerator.GetInt32(1, int.MaxValue);
        var generationSeed = DungeonSeedDeriver.GenerationSeed(baseSeed, tier, 1);
        var runId = Guid.NewGuid();

        string json;
        string? checksum;
        try
        {
            (json, checksum) = _generator.Generate(biomeId, generationSeed, tier, playerLevel, runId);
        }
        catch (Exception ex)
        {
            var correlationId = Guid.NewGuid();
            _logger.LogError(
                ex,
                "Dungeon generation failed (correlationId={CorrelationId}, biomeId={BiomeId}, tier={Tier})",
                correlationId,
                biomeId,
                tier);
            return new CreateRunResult(
                false,
                Error: $"generation_failed (reference: {correlationId})",
                IsInternalError: true);
        }

        var lootIds = LootInstanceIds.ParseLoot(json).Keys.ToArray();
        var run = new Run
        {
            Id = runId,
            AccountId = accountId,
            BiomeId = biomeId,
            Seed = baseSeed,
            Tier = tier,
            PlayerLevelSnapshot = playerLevel,
            Status = RunStatus.Active,
            CreatedAt = DateTimeOffset.UtcNow,
            DefinitionChecksum = checksum,
            LootInstanceIdsJson = JsonSerializer.Serialize(lootIds),
        };
        _db.Set<Run>().Add(run);
        await _db.SaveChangesAsync(ct);
        await _cache.SetAsync(runId, 1, json, CacheTtl, ct);

        ApiMetrics.RunsCreated.Add(1);
        return new CreateRunResult(true, runId, baseSeed, biomeId, json);
    }

    public async Task<string?> GetDungeonDefinitionAsync(Guid accountId, Guid runId, int floor = 1, CancellationToken ct = default)
    {
        var run = await _db.Set<Run>()
            .FirstOrDefaultAsync(r => r.Id == runId && r.AccountId == accountId, ct);
        if (run == null)
            return null;

        floor = Math.Max(1, floor);
        var cached = await _cache.GetAsync(runId, floor, ct);
        if (cached != null)
            return cached;

        var generationSeed = GenerationSeedFor(run, floor);
        var (json, _) = _generator.Generate(
            run.BiomeId,
            generationSeed,
            run.Tier,
            run.PlayerLevelSnapshot,
            run.Id,
            floor);
        await _cache.SetAsync(runId, floor, json, CacheTtl, ct);
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
            return new CompleteRunResult(false, runId, Error: "Run not found.");
        if (run.Status is RunStatus.Completed or RunStatus.Abandoned)
            return new CompleteRunResult(false, runId, Error: "Run already completed.");

        if (input.Outcome is not ("escaped" or "died" or "abandoned"))
            return new CompleteRunResult(false, runId, Error: "Invalid outcome.");

        if (input.Outcome == "escaped" && !input.BossDefeated)
            return new CompleteRunResult(false, runId, Error: "Boss must be defeated to escape.");

        if (input.ElapsedSeconds < 0 || input.ElapsedSeconds > 86_400)
            return new CompleteRunResult(false, runId, Error: "Invalid elapsed time.");

        if (input.LootClaimedInstanceIds.Count > 64)
            return new CompleteRunResult(false, runId, Error: "Too many loot claims.");

        if (input.LootClaimedInstanceIds.Distinct(StringComparer.OrdinalIgnoreCase).Count()
            != input.LootClaimedInstanceIds.Count)
        {
            ApiMetrics.LootClaimsRejected.Add(1);
            return new CompleteRunResult(false, runId, Error: "Duplicate loot instance id.");
        }

        if (input.Outcome == "escaped" && input.ElapsedSeconds < 5)
            return new CompleteRunResult(false, runId, Error: "Elapsed time too short for escape.");

        foreach (var lootId in input.LootClaimedInstanceIds)
        {
            if (string.IsNullOrWhiteSpace(lootId) || !Guid.TryParse(lootId, out _))
                return new CompleteRunResult(false, runId, Error: "Invalid loot instance id.");
        }

        var persistedLootIds = ParsePersistedLootIds(run.LootInstanceIdsJson);
        foreach (var lootId in input.LootClaimedInstanceIds)
        {
            if (!persistedLootIds.Contains(lootId))
            {
                ApiMetrics.LootClaimsRejected.Add(1);
                return new CompleteRunResult(false, runId, Error: "Unknown loot instance id.");
            }
        }

        var completedFloor = Math.Max(1, input.Floor);
        var definitionJson = await _cache.GetAsync(runId, completedFloor, ct);
        if (definitionJson == null)
        {
            var generationSeed = GenerationSeedFor(run, completedFloor);
            (definitionJson, _) = _generator.Generate(
                run.BiomeId,
                generationSeed,
                run.Tier,
                run.PlayerLevelSnapshot,
                run.Id,
                completedFloor);
        }

        var lootMap = LootInstanceIds.ParseLoot(definitionJson);

        var account = await _db.Set<Account>()
            .Include(a => a.SaveBlob)
            .FirstOrDefaultAsync(a => a.Id == accountId, ct);
        if (account == null)
            return new CompleteRunResult(false, runId, Error: "Account not found.");

        var state = account.SaveBlob != null
            ? SaveService.ParseState(account.SaveBlob.JsonData, accountId)
            : CharacterStateDefaults.Create(accountId);

        var progression = ProgressionApplier.ApplyRunOutcome(
            state,
            input.Outcome,
            run.Tier,
            input.LootClaimedInstanceIds,
            lootMap);

        var talentError = TalentValidator.ValidateTalents(state);
        if (talentError != null)
            return new CompleteRunResult(false, runId, Error: talentError);

        var now = DateTimeOffset.UtcNow;
        var stateJson = state.ToJsonString(new JsonSerializerOptions { WriteIndented = false });
        if (account.SaveBlob == null)
        {
            account.SaveBlob = new SaveBlob
            {
                AccountId = accountId,
                JsonData = stateJson,
                UpdatedAt = now,
            };
        }
        else
        {
            account.SaveBlob.JsonData = stateJson;
            account.SaveBlob.UpdatedAt = now;
        }

        run.Status = input.Outcome == "abandoned" ? RunStatus.Abandoned : RunStatus.Completed;
        run.CompletedAt = now;
        await _db.SaveChangesAsync(ct);

        ApiMetrics.RunsCompleted.Add(1);
        var statusLabel = input.Outcome == "abandoned" ? "abandoned" : "completed";
        return new CompleteRunResult(
            true,
            runId,
            statusLabel,
            progression with { CharacterStateJson = stateJson });
    }

    private static HashSet<string> ParsePersistedLootIds(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
            return new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        try
        {
            var ids = JsonSerializer.Deserialize<string[]>(json) ?? [];
            return ids.ToHashSet(StringComparer.OrdinalIgnoreCase);
        }
        catch
        {
            return new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        }
    }
}

public class ProceduralDungeonGenerator : IDungeonGenerator
{
    public (string Json, string? Checksum) Generate(
        string biomeId,
        int seed,
        int tier,
        int playerLevel,
        Guid runId,
        int floorIndex = 1,
        bool isFinalFloor = false)
    {
        var result = DungeonGenerator.Generate(
            biomeId, seed, tier, playerLevel, runId, floorIndex, isFinalFloor);
        return (result.Json, result.Definition.Checksum);
    }
}
