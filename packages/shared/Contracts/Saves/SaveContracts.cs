namespace Aumbrye.Shared.Contracts.Saves;

public sealed record SaveResponse(
    string StateJson,
    DateTimeOffset UpdatedAt,
    long Revision = 0);

public sealed record PutSaveRequest(
    string StateJson,
    DateTimeOffset? ClientUpdatedAt,
    long? ClientRevision = null);

public sealed record PutSaveResponse(
    DateTimeOffset UpdatedAt,
    bool Conflict = false,
    string? ServerStateJson = null,
    long Revision = 0);
