namespace Aumbrye.Procedural.Content;

public static class ContentPaths
{
    public static string Root { get; } = FindContentRoot(AppContext.BaseDirectory);

    public static string Biomes => Path.Combine(Root, "biomes");

    public static string Enemies => Path.Combine(Root, "enemies");

    public static string Bosses => Path.Combine(Root, "bosses");

    public static string Items => Path.Combine(Root, "items");

    internal static string FindContentRoot(string baseDirectory)
    {
        var envRoot = Environment.GetEnvironmentVariable("AUMBRYE_CONTENT_ROOT");
        if (!string.IsNullOrWhiteSpace(envRoot) && Directory.Exists(envRoot))
            return Path.GetFullPath(envRoot);

        var dir = new DirectoryInfo(baseDirectory);
        while (dir != null)
        {
            var content = Path.Combine(dir.FullName, "content");
            if (Directory.Exists(content))
                return content;
            dir = dir.Parent;
        }

        throw new InvalidOperationException(
            $"Could not locate content/ directory. Searched upward from '{baseDirectory}'.\n" +
            "Set AUMBRYE_CONTENT_ROOT to an absolute path containing biomes/, enemies/, items/.");
    }
}
