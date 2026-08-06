namespace Aumbrye.Infrastructure.Security;

public static class JwtSigningKey
{
    public const int MinimumDecodedBytes = 32;

    internal const string InMemoryTestSecret =
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==";

    public static byte[] FromSecret(string secret)
    {
        if (string.IsNullOrWhiteSpace(secret))
            throw new InvalidOperationException("Jwt:Secret is required.");

        byte[] decoded;
        try
        {
            decoded = Convert.FromBase64String(secret);
        }
        catch (FormatException ex)
        {
            throw new InvalidOperationException("Jwt:Secret must be a valid base64 string.", ex);
        }

        if (decoded.Length < MinimumDecodedBytes)
        {
            throw new InvalidOperationException(
                $"Jwt:Secret must decode to at least {MinimumDecodedBytes} bytes.");
        }

        return decoded;
    }

    public static byte[] FromConfiguration(
        Microsoft.Extensions.Configuration.IConfiguration configuration,
        bool useInMemoryStores)
    {
        var secret = configuration["Jwt:Secret"];
        if (string.IsNullOrWhiteSpace(secret))
        {
            if (useInMemoryStores)
                return FromSecret(InMemoryTestSecret);
            throw new InvalidOperationException(
                "Jwt:Secret must be set via configuration or environment (Jwt__Secret).");
        }

        return FromSecret(secret);
    }
}
