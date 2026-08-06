using Aumbrye.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Aumbrye.IntegrationTests;

public class MigrationTests : IClassFixture<AumbryeWebApplicationFactory>
{
    private readonly AumbryeWebApplicationFactory _factory;

    public MigrationTests(AumbryeWebApplicationFactory factory) => _factory = factory;

    [Fact]
    public void ModelHasNoPendingChanges()
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AumbryeDbContext>();
        var migrations = db.Database.GetMigrations().ToList();
        Assert.Equal(3, migrations.Count);
        Assert.Equal("20260805120002_AddAccountDisplayNameAndTokenFamily", migrations.Last());
    }
}
