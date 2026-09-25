using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Aumbrye.Infrastructure.Persistence;

#nullable disable

namespace Aumbrye.Infrastructure.Persistence.Migrations;

[DbContext(typeof(AumbryeDbContext))]
[Migration("20260923100000_RunProgressionVerification")]
public partial class RunProgressionVerification : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<bool>(
            name: "RankedProgressionVerified",
            table: "Runs",
            type: "boolean",
            nullable: false,
            defaultValue: false);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(
            name: "RankedProgressionVerified",
            table: "Runs");
    }
}
