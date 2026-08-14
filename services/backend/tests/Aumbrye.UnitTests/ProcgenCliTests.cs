using System.Diagnostics;
using System.Runtime.InteropServices;
using Aumbrye.ProcgenCli;
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
    public void ParseGenerateArgs_AcceptsFloorFlag()
    {
        var options = ProcgenCliArgs.ParseGenerateArgs(["generate", "forgotten_castle", "42", "--floor", "3"]);
        Assert.Equal(3, options.FloorIndex);
        Assert.False(options.IsFinalFloor);
    }

    [Fact]
    public void ParseGenerateArgs_AcceptsFinalFloorFlag()
    {
        var options = ProcgenCliArgs.ParseGenerateArgs(["generate", "forgotten_castle", "42", "--final-floor"]);
        Assert.True(options.IsFinalFloor);
    }

    [Fact]
    public void ParseGenerateArgs_RejectsUnknownArgument()
    {
        var ex = Assert.Throws<ArgumentException>(() =>
            ProcgenCliArgs.ParseGenerateArgs(["generate", "forgotten_castle", "42", "--nope"]));
        Assert.Contains("Unknown argument", ex.Message);
    }

    [Fact]
    public void ParseGenerateArgs_RejectsNonIntegerSeed()
    {
        var ex = Assert.Throws<ArgumentException>(() =>
            ProcgenCliArgs.ParseGenerateArgs(["generate", "forgotten_castle", "abc"]));
        Assert.Contains("Seed", ex.Message);
    }

    [Fact]
    public void PublishedOrDebugBinary_ExistsAfterBuild()
    {
        var binary = FindProcgenCliBinary();
        Assert.NotNull(binary);
    }

    private static string ProcgenCliBinaryFileName =>
        RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? "procgen-cli.exe" : "procgen-cli";

    /// <summary>
    /// Locates the CLI without hardcoding a target framework.
    /// </summary>
    /// <remarks>
    /// The copy next to the test assembly is preferred because the build guarantees it matches the
    /// library under test. Pinning "net8.0" here meant that after the move to net10.0 the test
    /// silently picked up stale build output from the previous framework.
    /// </remarks>
    private static string? FindProcgenCliBinary()
    {
        var name = ProcgenCliBinaryFileName;

        var alongsideTests = Path.Combine(AppContext.BaseDirectory, name);
        if (File.Exists(alongsideTests))
            return alongsideTests;

        var cliDir = Path.Combine(FindRepoRoot(), "tools", "procgen-cli");
        var published = Path.Combine(cliDir, "publish", name);
        if (File.Exists(published))
            return published;

        var binDir = Path.Combine(cliDir, "bin");
        if (!Directory.Exists(binDir))
            return null;

        return Directory.EnumerateFiles(binDir, name, SearchOption.AllDirectories)
            .OrderByDescending(File.GetLastWriteTimeUtc)
            .FirstOrDefault();
    }

    /// <summary>
    /// Points a spawned apphost at the runtime hosting this test run, so a side-by-side or
    /// user-local .NET install resolves the same way it does for the test host itself.
    /// </summary>
    private static void ForwardDotnetRoot(ProcessStartInfo startInfo)
    {
        if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("DOTNET_ROOT")))
            return;

        var host = Environment.ProcessPath;
        if (string.IsNullOrEmpty(host))
            return;

        var hostDir = Path.GetDirectoryName(host);
        if (!string.IsNullOrEmpty(hostDir) && Directory.Exists(Path.Combine(hostDir, "shared")))
            startInfo.Environment["DOTNET_ROOT"] = hostDir;
    }

    private static (int ExitCode, string Stdout, string Stderr) RunCli(string csproj, string args)
    {
        ProcessStartInfo startInfo;
        var binary = FindProcgenCliBinary();
        if (binary != null)
        {
            startInfo = new ProcessStartInfo
            {
                FileName = binary,
                Arguments = args,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };
            ForwardDotnetRoot(startInfo);
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
