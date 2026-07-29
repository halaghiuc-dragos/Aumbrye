using Aumbrye.Shared.Contracts;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddEndpointsApiExplorer();

var app = builder.Build();

app.MapGet("/api/v1/health", () => Results.Ok(new HealthResponse("ok")));

app.Run();

public partial class Program;
