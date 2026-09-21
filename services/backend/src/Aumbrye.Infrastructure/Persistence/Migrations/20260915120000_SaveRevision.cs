using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Aumbrye.Infrastructure.Persistence.Migrations;

public partial class SaveRevision : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<long>(
            name: "Revision",
            table: "SaveBlobs",
            type: "bigint",
            nullable: false,
            defaultValue: 0L);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(name: "Revision", table: "SaveBlobs");
    }
}
