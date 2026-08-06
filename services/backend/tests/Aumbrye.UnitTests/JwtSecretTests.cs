using Aumbrye.Application.Services;
using Aumbrye.Infrastructure.Security;
using Xunit;

namespace Aumbrye.UnitTests;

public class JwtSecretTests
{
    [Fact]
    public void ShortSecret_Throws()
    {
        var shortSecret = Convert.ToBase64String(new byte[16]);
        Assert.Throws<InvalidOperationException>(() => JwtSigningKey.FromSecret(shortSecret));
    }

    [Fact]
    public void LongSecret_UsesAllBytes()
    {
        var secretA = Convert.ToBase64String(Enumerable.Range(0, 64).Select(i => (byte)i).ToArray());
        var secretB = Convert.ToBase64String(Enumerable.Range(0, 64).Select(i => (byte)(i + 1)).ToArray());

        var keyA = JwtSigningKey.FromSecret(secretA);
        var keyB = JwtSigningKey.FromSecret(secretB);

        Assert.Equal(64, keyA.Length);
        Assert.Equal(64, keyB.Length);
        Assert.False(keyA.SequenceEqual(keyB));
        Assert.False(keyA.Take(32).SequenceEqual(keyB.Take(32)));
    }
}

public class LeaderboardMemberTests
{
    [Fact]
    public void RoundTripsAccountTimestampAndName()
    {
        var accountId = Guid.Parse("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee");
        var submittedAt = DateTimeOffset.Parse("2026-08-05T12:00:00Z");
        var displayName = "Wanderer-abc123";

        var member = LeaderboardMemberFormat.Format(accountId, submittedAt, displayName);
        Assert.True(LeaderboardMemberFormat.TryParse(member, out var parsedId, out var parsedAt, out var parsedName));
        Assert.Equal(accountId, parsedId);
        Assert.Equal(submittedAt.ToUnixTimeSeconds(), parsedAt.ToUnixTimeSeconds());
        Assert.Equal(displayName, parsedName);
    }
}
