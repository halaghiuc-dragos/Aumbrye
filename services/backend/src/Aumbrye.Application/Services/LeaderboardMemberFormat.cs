namespace Aumbrye.Application.Services;

public static class LeaderboardMemberFormat
{
    public static string Format(Guid accountId, DateTimeOffset submittedAt, string displayName) =>
        $"{accountId:N}|{submittedAt.ToUnixTimeSeconds()}|{displayName}";

    public static bool TryParse(string member, out Guid accountId, out DateTimeOffset submittedAt, out string displayName)
    {
        accountId = default;
        submittedAt = default;
        displayName = string.Empty;

        var parts = member.Split('|', 3);
        if (parts.Length < 2 || !Guid.TryParse(parts[0], out accountId))
            return false;

        if (!long.TryParse(parts[1], out var unixSeconds))
            return false;

        submittedAt = DateTimeOffset.FromUnixTimeSeconds(unixSeconds);
        displayName = parts.Length == 3 ? parts[2] : accountId.ToString()[..8];
        return true;
    }
}
