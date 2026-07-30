namespace Aumbrye.Shared.Contracts.Saves;

public sealed record SaveResponse(
    string StateJson,
    DateTimeOffset UpdatedAt);

public sealed record PutSaveRequest(
    string StateJson,
    DateTimeOffset? ClientUpdatedAt);

public sealed record PutSaveResponse(
    DateTimeOffset UpdatedAt,
    bool Conflict = false);
