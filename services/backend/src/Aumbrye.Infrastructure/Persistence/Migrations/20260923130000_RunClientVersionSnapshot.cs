using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Aumbrye.Infrastructure.Persistence;

#nullable disable

namespace Aumbrye.Infrastructure.Persistence.Migrations;

[DbContext(typeof(AumbryeDbContext))]
[Migration("20260923130000_RunClientVersionSnapshot")]
public partial class RunClientVersionSnapshot : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<string>(
            name: "ClientVersionSnapshot",
            table: "Runs",
            type: "character varying(64)",
            maxLength: 64,
            nullable: false,
            defaultValue: "legacy-unknown");
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(
            name: "ClientVersionSnapshot",
            table: "Runs");
    }
}
