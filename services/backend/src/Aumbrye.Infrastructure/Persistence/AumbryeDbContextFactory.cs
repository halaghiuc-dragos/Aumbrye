using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace Aumbrye.Infrastructure.Persistence;

public sealed class AumbryeDbContextFactory : IDesignTimeDbContextFactory<AumbryeDbContext>
{
    public AumbryeDbContext CreateDbContext(string[] args) =>
        new(new DbContextOptionsBuilder<AumbryeDbContext>()
            .UseNpgsql(Environment.GetEnvironmentVariable("ConnectionStrings__DefaultConnection")
                       ?? "Host=localhost;Port=5432;Database=aumbrye;Username=aumbrye;Password=aumbrye_dev")
            .Options);
}
