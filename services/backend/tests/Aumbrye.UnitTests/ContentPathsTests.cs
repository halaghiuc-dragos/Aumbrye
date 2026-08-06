using Aumbrye.Procedural.Content;
using Xunit;

namespace Aumbrye.UnitTests;

public class ContentPathsTests
{
    [Fact]
    public void FindContentRoot_ThrowsWithActionableMessage_WhenAbsent()
    {
        var temp = Path.Combine(Path.GetTempPath(), "aumbrye-contentpaths-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(temp);
        try
        {
            var ex = Assert.Throws<InvalidOperationException>(() => ContentPaths.FindContentRoot(temp));
            Assert.Contains("Could not locate content/ directory.", ex.Message);
            Assert.Contains(temp, ex.Message);
            Assert.Contains("AUMBRYE_CONTENT_ROOT", ex.Message);
            Assert.Contains("biomes/", ex.Message);
        }
        finally
        {
            Directory.Delete(temp, recursive: true);
        }
    }
}
