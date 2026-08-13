using System.Text.Json;
using System.Text.RegularExpressions;
using Aumbrye.Application.Services;
using Aumbrye.Shared.Contracts;
using Xunit;

namespace Aumbrye.UnitTests;

public class ClientVersionParityTests
{
    [Fact]
    public void BackendCharacterStateVersion_MatchesClientSaveMigrator()
    {
        var repoRoot = FindRepoRoot(AppContext.BaseDirectory);
        var migratorPath = Path.Combine(
            repoRoot, "apps", "game", "client", "scripts", "save", "save_migrator.gd");
        var migratorSource = File.ReadAllText(migratorPath);

        var match = Regex.Match(migratorSource, @"const\s+CURRENT_VERSION\s*:=\s*(\d+)");
        Assert.True(match.Success, $"Could not find CURRENT_VERSION in {migratorPath}");
        var clientVersion = int.Parse(match.Groups[1].Value);

        Assert.Equal(clientVersion, CharacterStateDefaults.SchemaVersion);
    }

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

    private static string FindRepoRoot(string baseDirectory)
    {
        var dir = new DirectoryInfo(baseDirectory);
        while (dir != null)
        {
            if (Directory.Exists(Path.Combine(dir.FullName, "content"))
                && Directory.Exists(Path.Combine(dir.FullName, "apps")))
                return dir.FullName;
            dir = dir.Parent;
        }

        throw new InvalidOperationException(
            $"Could not locate the repository root. Searched upward from '{baseDirectory}'.");
    }
}
