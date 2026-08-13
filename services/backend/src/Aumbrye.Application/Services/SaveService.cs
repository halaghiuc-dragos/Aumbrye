using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Aumbrye.Application.Abstractions;
using Aumbrye.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace Aumbrye.Application.Services;

/// <summary>
/// Outcome of reading a stored save blob. <see cref="Corrupt"/> distinguishes "this account has
/// no save yet" from "this account's save could not be read" — collapsing the two is what let a
/// truncated row silently become a fresh level-1 character.
/// </summary>
public sealed record SaveParseResult(JsonObject State, bool Corrupt);

public class SaveService : ISaveService
{
    private readonly DbContext _db;
    private readonly ILogger<SaveService> _logger;

    public SaveService(DbContext db, ILogger<SaveService> logger)
    {
        _db = db;
        _logger = logger;
    }

    public async Task<SaveGetResult> GetCurrentAsync(Guid accountId, CancellationToken ct = default)
    {
        var account = await _db.Set<Account>()
            .Include(a => a.SaveBlob)
            .FirstOrDefaultAsync(a => a.Id == accountId, ct);
        if (account == null)
            return new SaveGetResult(false, Error: "Account not found.");

        if (account.SaveBlob == null)
        {
            var defaultState = CharacterStateDefaults.Create(accountId);
            return new SaveGetResult(true, defaultState, DateTimeOffset.UtcNow);
        }

        var parsed = ParseState(account.SaveBlob.JsonData, accountId);
        if (parsed.Corrupt)
        {
            // Never hand back a default character here. The client would treat it as authoritative
            // and its next PUT would overwrite whatever was still recoverable.
            await QuarantineAsync(_db, accountId, account.SaveBlob.JsonData, "get_current_parse_failure", ct);
            _logger.LogError(
                "Save blob for account {AccountId} is unreadable; quarantined and refused.", accountId);
            return new SaveGetResult(false, Error: "save_corrupt", ErrorStatus: 422);
        }

        return new SaveGetResult(true, parsed.State, account.SaveBlob.UpdatedAt);
    }

    public async Task<SavePutResult> PutCurrentAsync(
        Guid accountId,
        JsonObject state,
        DateTimeOffset? clientUpdatedAt,
        CancellationToken ct = default)
    {
        var account = await _db.Set<Account>()
            .Include(a => a.SaveBlob)
            .FirstOrDefaultAsync(a => a.Id == accountId, ct);
        if (account == null)
            return new SavePutResult(false, Error: "Account not found.");

        state["accountId"] = accountId.ToString();
        state["schemaVersion"] = CharacterStateDefaults.SchemaVersion;

        var validationError = SaveStateValidator.Validate(state);
        if (validationError != null)
            return new SavePutResult(false, Error: validationError);

        if (account.SaveBlob != null
            && clientUpdatedAt.HasValue
            && account.SaveBlob.UpdatedAt > clientUpdatedAt.Value)
        {
            var parsed = ParseState(account.SaveBlob.JsonData, accountId);
            if (parsed.Corrupt)
            {
                await QuarantineAsync(_db, accountId, account.SaveBlob.JsonData, "put_conflict_parse_failure", ct);
                // The server copy is unreadable, so it cannot win the conflict; let the client's
                // write through rather than handing back a default as "the server state".
                _logger.LogError(
                    "Server save for account {AccountId} was unreadable during a conflict; accepting client write.",
                    accountId);
            }
            else
            {
                return new SavePutResult(
                    false,
                    parsed.State,
                    account.SaveBlob.UpdatedAt,
                    Conflict: true,
                    Error: "Server save is newer; server wins.");
            }
        }

        var json = state.ToJsonString(new JsonSerializerOptions { WriteIndented = false });
        var now = DateTimeOffset.UtcNow;
        if (account.SaveBlob == null)
        {
            account.SaveBlob = new SaveBlob
            {
                AccountId = accountId,
                JsonData = json,
                UpdatedAt = now,
            };
        }
        else
        {
            account.SaveBlob.JsonData = json;
            account.SaveBlob.UpdatedAt = now;
        }

        await _db.SaveChangesAsync(ct);
        return new SavePutResult(true, state, now);
    }

    /// <summary>
    /// Parses a stored save blob. Callers must inspect <see cref="SaveParseResult.Corrupt"/>: the
    /// returned default state is a placeholder to keep call sites total, never a replacement save.
    /// </summary>
    internal static SaveParseResult ParseState(string json, Guid accountId)
    {
        try
        {
            if (JsonNode.Parse(json) is JsonObject obj)
                return new SaveParseResult(obj, Corrupt: false);
        }
        catch (JsonException)
        {
        }

        return new SaveParseResult(CharacterStateDefaults.Create(accountId), Corrupt: true);
    }

    /// <summary>
    /// Copies an unreadable blob into the quarantine table so the raw bytes survive for support
    /// and forensics. Best-effort: a quarantine failure must not mask the original problem.
    /// </summary>
    internal static async Task QuarantineAsync(
        DbContext db,
        Guid accountId,
        string rawJson,
        string reason,
        CancellationToken ct)
    {
        try
        {
            var alreadyCaptured = await db.Set<SaveBlobQuarantine>()
                .AnyAsync(q => q.AccountId == accountId && q.RawJson == rawJson, ct);
            if (alreadyCaptured)
                return;

            db.Set<SaveBlobQuarantine>().Add(new SaveBlobQuarantine
            {
                Id = Guid.NewGuid(),
                AccountId = accountId,
                CapturedAt = DateTimeOffset.UtcNow,
                RawJson = rawJson,
                Reason = reason,
            });
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException)
        {
            // Swallowed deliberately — the caller is already reporting the real failure.
        }
    }

    /// <summary>UTF-8 byte length of a save body, for the request size cap.</summary>
    public static int ByteLength(string json) => Encoding.UTF8.GetByteCount(json);
}
