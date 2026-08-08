using System.Text.Json;
using Aumbrye.Shared.Contracts;
using Xunit;

namespace Aumbrye.UnitTests;

public class ClientVersionParityTests
{
    [Fact]
    public void PackageJsonVersion_MatchesExpectedClientVersion()
    {
        var packageJsonPath = FindWebPackageJson(AppContext.BaseDirectory);
        using var document = JsonDocument.Parse(File.ReadAllText(packageJsonPath));
        var packageVersion = document.RootElement.GetProperty("version").GetString();

        Assert.Equal(ApiVersions.ExpectedClientVersion, packageVersion);
    }

    private static string FindWebPackageJson(string baseDirectory)
    {
        var dir = new DirectoryInfo(baseDirectory);
        while (dir != null)
        {
            var candidate = Path.Combine(dir.FullName, "apps", "web", "package.json");
            if (File.Exists(candidate))
                return candidate;
            dir = dir.Parent;
        }

        throw new InvalidOperationException(
            $"Could not locate apps/web/package.json. Searched upward from '{baseDirectory}'.");
    }
}
