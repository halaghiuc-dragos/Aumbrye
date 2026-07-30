using System.Text.Json;
using System.Text.Json.Nodes;
using Aumbrye.Application.Abstractions;
using Aumbrye.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace Aumbrye.Application.Services;

public class SaveService : ISaveService
{
    private readonly DbContext _db;

    public SaveService(DbContext db) => _db = db;

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

        var state = ParseState(account.SaveBlob.JsonData, accountId);
        return new SaveGetResult(true, state, account.SaveBlob.UpdatedAt);
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
        state["schemaVersion"] = 1;

        var talentError = TalentValidator.ValidateTalents(state);
        if (talentError != null)
            return new SavePutResult(false, Error: talentError);

        if (account.SaveBlob != null
            && clientUpdatedAt.HasValue
            && account.SaveBlob.UpdatedAt > clientUpdatedAt.Value)
        {
            var serverState = ParseState(account.SaveBlob.JsonData, accountId);
            return new SavePutResult(
                false,
                serverState,
                account.SaveBlob.UpdatedAt,
                Conflict: true,
                Error: "Server save is newer; server wins.");
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

    internal static JsonObject ParseState(string json, Guid accountId)
    {
        try
        {
            var node = JsonNode.Parse(json);
            if (node is JsonObject obj)
                return obj;
        }
        catch (JsonException)
        {
        }

        return CharacterStateDefaults.Create(accountId);
    }
}
