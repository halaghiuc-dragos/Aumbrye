using System.Text.Json.Nodes;
using Aumbrye.Application.Services;
using Xunit;

namespace Aumbrye.UnitTests;

public class TalentValidationTests
{
    [Fact]
    public void ValidTalents_PassValidation()
    {
        var state = CharacterStateDefaults.Create(Guid.NewGuid());
        state["character"]!["level"] = 3;
        state["talents"] = new JsonObject { ["arms_1"] = 1 };
        Assert.Null(TalentValidator.ValidateTalents(state));
    }

    [Fact]
    public void UnknownNode_Rejected()
    {
        var state = CharacterStateDefaults.Create(Guid.NewGuid());
        state["talents"] = new JsonObject { ["fake_node"] = 1 };
        var error = TalentValidator.ValidateTalents(state);
        Assert.NotNull(error);
        Assert.Contains("Unknown", error);
    }

    [Fact]
    public void MissingPrerequisite_Rejected()
    {
        var state = CharacterStateDefaults.Create(Guid.NewGuid());
        state["character"]!["level"] = 10;
        state["talents"] = new JsonObject { ["arms_2"] = 1 };
        var error = TalentValidator.ValidateTalents(state);
        Assert.NotNull(error);
        Assert.Contains("requires", error, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void OverspentPoints_Rejected()
    {
        var state = CharacterStateDefaults.Create(Guid.NewGuid());
        state["character"]!["level"] = 2;
        state["talents"] = new JsonObject
        {
            ["arms_1"] = 1,
            ["guard_1"] = 1,
        };
        var error = TalentValidator.ValidateTalents(state);
        Assert.NotNull(error);
        Assert.Contains("talent points", error, StringComparison.OrdinalIgnoreCase);
    }
}
