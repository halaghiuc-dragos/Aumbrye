using Aumbrye.Application.Abstractions;
using Aumbrye.Application.Services;
using Aumbrye.Infrastructure.Caching;
using Aumbrye.Infrastructure.Persistence;
using Aumbrye.Infrastructure.Security;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using StackExchange.Redis;

namespace Aumbrye.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration,
        bool useInMemoryStores = false)
    {
        if (useInMemoryStores)
        {
            services.AddSingleton(_ =>
            {
                var connection = new SqliteConnection("Data Source=:memory:;Cache=Shared");
                connection.Open();
                return connection;
            });
            services.AddDbContext<AumbryeDbContext>((sp, options) =>
                options.UseSqlite(sp.GetRequiredService<SqliteConnection>()));
            services.AddScoped<DbContext>(sp => sp.GetRequiredService<AumbryeDbContext>());
            services.AddSingleton<IDungeonCache, InMemoryDungeonCache>();
        }
        else
        {
            services.AddDbContext<AumbryeDbContext>(options =>
                options.UseNpgsql(configuration.GetConnectionString("DefaultConnection")));
            services.AddScoped<DbContext>(sp => sp.GetRequiredService<AumbryeDbContext>());
            var redisConn = configuration.GetConnectionString("Redis");
            if (!string.IsNullOrWhiteSpace(redisConn))
            {
                services.AddSingleton<IConnectionMultiplexer>(_ =>
                    ConnectionMultiplexer.Connect(redisConn));
                services.AddSingleton<IDungeonCache, RedisDungeonCache>();
            }
            else
            {
                services.AddSingleton<IDungeonCache, InMemoryDungeonCache>();
            }
        }

        services.AddScoped<IPasswordHasher, BcryptPasswordHasher>();
        services.AddSingleton<ITokenService, JwtTokenService>();
        services.AddScoped<IAuthService, AuthService>();
        services.AddSingleton<IDungeonGenerator, ProceduralDungeonGenerator>();
        services.AddScoped<IRunService, RunService>();
        services.AddScoped<ISaveService, SaveService>();

        return services;
    }

    public static void ApplyDatabaseSchema(this IServiceProvider services)
    {
        using var scope = services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AumbryeDbContext>();
        db.Database.EnsureCreated();
    }
}
