using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Aumbrye.Infrastructure.Persistence.Migrations;

public partial class RankedDefinitionEligibility : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<bool>(
            name: "RankedDefinitionEligible",
            table: "Runs",
            type: "boolean",
            nullable: false,
            defaultValue: false);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(
            name: "RankedDefinitionEligible",
            table: "Runs");
    }
}
