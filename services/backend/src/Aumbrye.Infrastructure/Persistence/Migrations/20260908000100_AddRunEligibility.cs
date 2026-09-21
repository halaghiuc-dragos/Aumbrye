using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Aumbrye.Infrastructure.Persistence.Migrations;

public partial class AddRunEligibility : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<int>("Assists", "Runs", "integer", nullable: false, defaultValue: 0);
        migrationBuilder.AddColumn<bool>("FinalObjectiveCompleted", "Runs", "boolean", nullable: false, defaultValue: false);
        migrationBuilder.AddColumn<string>("Mode", "Runs", "character varying(32)", maxLength: 32, nullable: false, defaultValue: "dungeon");
        migrationBuilder.AddColumn<string>("Outcome", "Runs", "character varying(16)", maxLength: 16, nullable: true);
        migrationBuilder.AddColumn<string>("Ruleset", "Runs", "character varying(64)", maxLength: 64, nullable: false, defaultValue: "standard-v1");
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn("Assists", "Runs");
        migrationBuilder.DropColumn("FinalObjectiveCompleted", "Runs");
        migrationBuilder.DropColumn("Mode", "Runs");
        migrationBuilder.DropColumn("Outcome", "Runs");
        migrationBuilder.DropColumn("Ruleset", "Runs");
    }
}
