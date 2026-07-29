using Aumbrye.Procedural;
using Xunit;

namespace Aumbrye.UnitTests;

public class ProceduralAssemblyTests
{
    [Fact]
    public void Version_IsDefined()
    {
        Assert.False(string.IsNullOrWhiteSpace(ProceduralAssembly.Version));
    }
}
