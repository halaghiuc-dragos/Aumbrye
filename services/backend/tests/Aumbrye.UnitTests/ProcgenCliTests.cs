using System.Diagnostics;
using Xunit;

namespace Aumbrye.UnitTests;

public class ProcgenCliTests
{
    [Fact]
    public void CliGenerate_MatchesLibrary_ForFixedSeed()
    {
        var repoRoot = FindRepoRoot();
        var csproj = Path.Combine(repoRoot, "tools", "procgen-cli", "ProcgenCli.csproj");
        Assert.True(File.Exists(csproj), $"Missing procgen CLI project at {csproj}");

        var runId = Guid.Parse("00000000-0000-4000-8000-000000000010");
        var (exitCode, stdout, stderr) = RunCli(csproj, $"generate forgotten_castle 42001 {runId}");
        Assert.Equal(0, exitCode);
        Assert.False(string.IsNullOrWhiteSpace(stdout), $"procgen-cli failed: {stderr}");

        var library = Aumbrye.Procedural.Generation.DungeonGenerator.Generate(
            "forgotten_castle", 42001, 1, 1, runId);

        Assert.Equal(library.Json.Trim(), stdout.Trim());
    }

    [Fact]
    public void CliRejectsInvalidSeed()
    {
        var repoRoot = FindRepoRoot();
        var csproj = Path.Combine(repoRoot, "tools", "procgen-cli", "ProcgenCli.csproj");
        var (exitCode, _, stderr) = RunCli(csproj, "generate forgotten_castle 0");
        Assert.NotEqual(0, exitCode);
        Assert.Contains("Seed", stderr, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void PublishedOrDebugBinary_ExistsAfterBuild()
    {
        var repoRoot = FindRepoRoot();
        var published = Path.Combine(repoRoot, "tools", "procgen-cli", "publish", "procgen-cli.exe");
        var debug = Path.Combine(repoRoot, "tools", "procgen-cli", "bin", "Debug", "net8.0", "procgen-cli.exe");
        Assert.True(File.Exists(published) || File.Exists(debug),
            "Build procgen-cli: dotnet build tools/procgen-cli/ProcgenCli.csproj");
    }

    private static (int ExitCode, string Stdout, string Stderr) RunCli(string csproj, string args)
    {
        var repoRoot = FindRepoRoot();
        var debugExe = Path.Combine(repoRoot, "tools", "procgen-cli", "bin", "Debug", "net8.0", "procgen-cli.exe");

        ProcessStartInfo startInfo;
        if (File.Exists(debugExe))
        {
            startInfo = new ProcessStartInfo
            {
                FileName = debugExe,
                Arguments = args,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };
        }
        else
        {
            startInfo = new ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = $"run --project \"{csproj}\" -- {args}",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };
        }

        using var process = Process.Start(startInfo);
        Assert.NotNull(process);
        var stdout = process.StandardOutput.ReadToEnd();
        var stderr = process.StandardError.ReadToEnd();
        process.WaitForExit(TimeSpan.FromMinutes(2));
        return (process.ExitCode, stdout, stderr);
    }

    private static string FindRepoRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null)
        {
            if (Directory.Exists(Path.Combine(dir.FullName, "content")))
                return dir.FullName;
            dir = dir.Parent;
        }

        throw new InvalidOperationException("Could not locate repository root.");
    }
}
