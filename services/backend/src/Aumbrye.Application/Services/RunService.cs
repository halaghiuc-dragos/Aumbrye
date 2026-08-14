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

    private static readonly JsonSerializerOptions CompletionJsonOptions = new()
    {
        WriteIndented = false,
    };

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
            var parsed = SaveService.ParseState(account.SaveBlob.JsonData, accountId);
            playerLevel = parsed.State["character"]?["level"]?.GetValue<int>() ?? 1;
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
            HighestFloorGenerated = 1,
            LootInstanceIdsJson = SerializeLootMap(MergeFloorLoot([], json, floor: 1)),
        };
        _db.Set<Run>().Add(run);
        await _db.SaveChangesAsync(ct);
        await _cache.SetAsync(runId, 1, json, CacheTtl, ct);

        ApiMetrics.RunsCreated.Add(1);
        return new CreateRunResult(true, runId, baseSeed, biomeId, json);
    }

    public async Task<DungeonDefinitionResult> GetDungeonDefinitionAsync(
        Guid accountId,
        Guid runId,
        int floor = 1,
        CancellationToken ct = default)
    {
        var run = await _db.Set<Run>()
            .FirstOrDefaultAsync(r => r.Id == runId && r.AccountId == accountId, ct);
        if (run == null)
            return new DungeonDefinitionResult(false, NotFound: true);

        var floorError = ValidateFloor(run, floor);
        if (floorError != null)
            return new DungeonDefinitionResult(false, Error: floorError);

        var json = await EnsureFloorAsync(run, floor, ct);
        return new DungeonDefinitionResult(true, json);
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
            return ReplayCompletion(run);

        if (input.Outcome is not ("escaped" or "died" or "abandoned"))
            return new CompleteRunResult(false, runId, Error: "Invalid outcome.");

        if (input.Outcome == "escaped" && !input.BossDefeated)
            return new CompleteRunResult(false, runId, Error: "Boss must be defeated to escape.");

        if (input.ElapsedSeconds < 0 || input.ElapsedSeconds > 86_400)
            return new CompleteRunResult(false, runId, Error: "Invalid elapsed time.");

        var now = DateTimeOffset.UtcNow;
        // The client's clock excludes pause and menu time, so it may legitimately report LESS than
        // the wall-clock window — but never more. The 30s slack absorbs clock skew.
        if (input.ElapsedSeconds > (now - run.CreatedAt).TotalSeconds + 30)
            return new CompleteRunResult(false, runId, Error: "Implausible elapsed time.");

        if (input.Kills < 0 || input.Kills > MaxKillsPerRun)
            return new CompleteRunResult(false, runId, Error: "Implausible kill count.");

        if (input.LootClaimedInstanceIds.Count > MaxLootClaims)
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

        var floorError = ValidateFloor(run, input.Floor);
        if (floorError != null)
            return new CompleteRunResult(false, runId, Error: floorError);

        // Make sure the completing floor has contributed its loot to the run's union. Every floor
        // the player actually visited was generated through this same path, so the union covers
        // claims made on earlier floors too — which the old single-floor lookup silently dropped.
        await EnsureFloorAsync(run, input.Floor, ct);
        var lootMap = ParsePersistedLoot(run.LootInstanceIdsJson);

        foreach (var lootId in input.LootClaimedInstanceIds)
        {
            if (!lootMap.ContainsKey(lootId))
            {
                ApiMetrics.LootClaimsRejected.Add(1);
                return new CompleteRunResult(false, runId, Error: "Unknown loot instance id.");
            }
        }

        var account = await _db.Set<Account>()
            .Include(a => a.SaveBlob)
            .FirstOrDefaultAsync(a => a.Id == accountId, ct);
        if (account == null)
            return new CompleteRunResult(false, runId, Error: "Account not found.");

        var targetStatus = input.Outcome == "abandoned" ? RunStatus.Abandoned : RunStatus.Completed;

        // Claim the run before granting anything. Two concurrent /complete calls both pass the
        // validation above; only the one whose guarded UPDATE matches an Active row proceeds, so
        // progression and loot are applied exactly once.
        var claimed = await _db.Set<Run>()
            .Where(r => r.Id == runId && r.AccountId == accountId && r.Status == RunStatus.Active)
            .ExecuteUpdateAsync(
                s => s
                    .SetProperty(r => r.Status, targetStatus)
                    .SetProperty(r => r.CompletedAt, now)
                    .SetProperty(r => r.ElapsedSeconds, input.ElapsedSeconds),
                ct);

        if (claimed == 0)
        {
            await _db.Entry(run).ReloadAsync(ct);
            return ReplayCompletion(run);
        }

        // Keep the tracked entity in step with the guarded update so the save below does not
        // resurrect the pre-claim values.
        run.Status = targetStatus;
        run.CompletedAt = now;
        run.ElapsedSeconds = input.ElapsedSeconds;

        try
        {
            var parsed = account.SaveBlob != null
                ? SaveService.ParseState(account.SaveBlob.JsonData, accountId)
                : new SaveParseResult(CharacterStateDefaults.Create(accountId), Corrupt: false);

            if (parsed.Corrupt)
            {
                await SaveService.QuarantineAsync(
                    _db, accountId, account.SaveBlob!.JsonData, "complete_run_parse_failure", ct);
                _logger.LogError(
                    "Quarantined unreadable save for account {AccountId} during run completion.", accountId);
            }

            var state = parsed.State;
            var progression = ProgressionApplier.ApplyRunOutcome(
                state,
                input.Outcome,
                input.LootClaimedInstanceIds,
                lootMap.ToDictionary(
                    kv => kv.Key,
                    kv => new LootInstanceIds.LootEntry(kv.Value.ItemId, kv.Value.Quantity),
                    StringComparer.OrdinalIgnoreCase));

            var talentError = TalentValidator.ValidateTalents(state);
            if (talentError != null)
                throw new RunCompletionRejectedException(talentError);

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

            var result = progression with { CharacterStateJson = stateJson };
            run.CompletionResultJson = JsonSerializer.Serialize(result, CompletionJsonOptions);
            await _db.SaveChangesAsync(ct);

            ApiMetrics.RunsCompleted.Add(1);
            var statusLabel = input.Outcome == "abandoned" ? "abandoned" : "completed";
            return new CompleteRunResult(true, runId, statusLabel, result);
        }
        catch (Exception ex)
        {
            // Release the claim so a rejected completion does not strand the run as finished with
            // no progression recorded.
            await _db.Set<Run>()
                .Where(r => r.Id == runId)
                .ExecuteUpdateAsync(
                    s => s
                        .SetProperty(r => r.Status, RunStatus.Active)
                        .SetProperty(r => r.CompletedAt, (DateTimeOffset?)null)
                        .SetProperty(r => r.ElapsedSeconds, (double?)null),
                    CancellationToken.None);
            _db.Entry(run).State = EntityState.Detached;

            if (ex is RunCompletionRejectedException rejected)
                return new CompleteRunResult(false, runId, Error: rejected.Message);
            throw;
        }
    }

    /// <summary>
    /// Upper bound on loot claims per completion. One chest-dense floor cannot approach this, and
    /// multi-floor runs accumulate claims across floors, so it is generous rather than tight.
    /// </summary>
    private const int MaxLootClaims = 256;

    /// <summary>
    /// Ceiling on self-reported kills. Runs are client-authoritative today, so this bounds how far
    /// a fabricated report can inflate XP rather than trusting the number outright.
    /// </summary>
    private const int MaxKillsPerRun = 5_000;

    /// <summary>
    /// Rejects floor indices that are out of range for the run. Without this a single caller can
    /// request floor=2000000 and force a full procedural generation plus a 24h cache entry per
    /// distinct value.
    /// </summary>
    private static string? ValidateFloor(Run run, int floor)
    {
        if (floor < 1 || floor > Run.MaxFloorsPerRun)
            return $"Floor must be between 1 and {Run.MaxFloorsPerRun}.";

        if (floor > run.HighestFloorGenerated + Run.FloorLookaheadLimit)
            return "Floor is too far ahead of this run's progress.";

        return null;
    }

    /// <summary>
    /// Returns the definition for a floor, generating and caching it on first request and folding
    /// its loot into the run's cumulative instance map.
    /// </summary>
    private async Task<string> EnsureFloorAsync(Run run, int floor, CancellationToken ct)
    {
        var cached = await _cache.GetAsync(run.Id, floor, ct);
        if (cached != null && floor <= run.HighestFloorGenerated)
            return cached;

        var json = cached;
        if (json == null)
        {
            var generationSeed = GenerationSeedFor(run, floor);
            (json, _) = _generator.Generate(
                run.BiomeId,
                generationSeed,
                run.Tier,
                run.PlayerLevelSnapshot,
                run.Id,
                floor);
            await _cache.SetAsync(run.Id, floor, json, CacheTtl, ct);
        }

        var merged = MergeFloorLoot(ParsePersistedLoot(run.LootInstanceIdsJson), json, floor);
        run.LootInstanceIdsJson = SerializeLootMap(merged);
        run.HighestFloorGenerated = Math.Max(run.HighestFloorGenerated, floor);
        await _db.SaveChangesAsync(ct);

        return json;
    }

    private CompleteRunResult ReplayCompletion(Run run)
    {
        var statusLabel = run.Status == RunStatus.Abandoned ? "abandoned" : "completed";
        if (string.IsNullOrWhiteSpace(run.CompletionResultJson))
            return new CompleteRunResult(false, run.Id, Error: "Run already completed.");

        try
        {
            var progression = JsonSerializer.Deserialize<RunProgressionResult>(
                run.CompletionResultJson, CompletionJsonOptions);
            // Replaying the original payload keeps a retried POST idempotent for the client rather
            // than surfacing a spurious failure after a network timeout.
            return new CompleteRunResult(true, run.Id, statusLabel, progression);
        }
        catch (JsonException ex)
        {
            _logger.LogWarning(ex, "Could not replay cached completion for run {RunId}.", run.Id);
            return new CompleteRunResult(false, run.Id, Error: "Run already completed.");
        }
    }

    private static Dictionary<string, PersistedLootEntry> MergeFloorLoot(
        Dictionary<string, PersistedLootEntry> existing,
        string definitionJson,
        int floor)
    {
        foreach (var (instanceId, entry) in LootInstanceIds.ParseLoot(definitionJson))
            existing[instanceId] = new PersistedLootEntry(entry.ItemId, entry.Quantity, floor);
        return existing;
    }

    private static string SerializeLootMap(Dictionary<string, PersistedLootEntry> map) =>
        JsonSerializer.Serialize(map);

    /// <summary>
    /// Reads the cumulative loot map, tolerating the legacy <c>["id", ...]</c> array shape written
    /// before floors were unioned so in-flight runs keep validating their claims.
    /// </summary>
    private static Dictionary<string, PersistedLootEntry> ParsePersistedLoot(string? json)
    {
        var map = new Dictionary<string, PersistedLootEntry>(StringComparer.OrdinalIgnoreCase);
        if (string.IsNullOrWhiteSpace(json))
            return map;

        try
        {
            using var document = JsonDocument.Parse(json);
            if (document.RootElement.ValueKind == JsonValueKind.Array)
            {
                foreach (var element in document.RootElement.EnumerateArray())
                {
                    var id = element.GetString();
                    if (!string.IsNullOrWhiteSpace(id))
                        map[id] = new PersistedLootEntry(string.Empty, 1, 1);
                }
                return map;
            }

            if (document.RootElement.ValueKind != JsonValueKind.Object)
                return map;

            foreach (var property in document.RootElement.EnumerateObject())
            {
                var itemId = property.Value.TryGetProperty("ItemId", out var itemIdEl)
                    ? itemIdEl.GetString() ?? string.Empty
                    : string.Empty;
                var quantity = property.Value.TryGetProperty("Quantity", out var qtyEl)
                                && qtyEl.TryGetInt32(out var q)
                    ? q
                    : 1;
                var floor = property.Value.TryGetProperty("Floor", out var floorEl)
                             && floorEl.TryGetInt32(out var f)
                    ? f
                    : 1;
                map[property.Name] = new PersistedLootEntry(itemId, quantity, floor);
            }
        }
        catch (JsonException)
        {
            // A corrupt map degrades to "no claims validate", which is the safe direction.
        }

        return map;
    }

    private sealed record PersistedLootEntry(string ItemId, int Quantity, int Floor);

    private sealed class RunCompletionRejectedException : Exception
    {
        public RunCompletionRejectedException(string message) : base(message) { }
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
