namespace Aumbrye.Application.Services;

/// <summary>
/// Sorted-set member encoding for leaderboard entries.
/// </summary>
/// <remarks>
/// A member is the bare account id, so a board holds at most one row per player and repeated
/// submissions update that player's best time in place instead of appending a new row. Volatile
/// metadata (display name, submission instant) lives in a companion hash keyed by the same id.
/// The legacy <c>accountId|unixSeconds|displayName</c> encoding is still parsed so boards written
/// before this change keep rendering until they are naturally rewritten.
/// </remarks>
public static class LeaderboardMemberFormat
{
    public static string Format(Guid accountId) => accountId.ToString("N");

    public static bool TryParse(string member, out Guid accountId)
    {
        var separator = member.IndexOf('|');
        var idPart = separator < 0 ? member : member[..separator];
        return Guid.TryParse(idPart, out accountId);
    }

    /// <summary>
    /// Reads the display name embedded in a legacy member string, if there is one. Returns null
    /// for the current bare-id encoding, where the name comes from the metadata hash instead.
    /// </summary>
    public static string? LegacyDisplayName(string member)
    {
        var parts = member.Split('|', 3);
        return parts.Length == 3 ? parts[2] : null;
    }

    /// <summary>Reads the submission instant embedded in a legacy member string, if there is one.</summary>
    public static DateTimeOffset? LegacySubmittedAt(string member)
    {
        var parts = member.Split('|', 3);
        if (parts.Length < 2 || !long.TryParse(parts[1], out var unixSeconds))
            return null;
        return DateTimeOffset.FromUnixTimeSeconds(unixSeconds);
    }
}
