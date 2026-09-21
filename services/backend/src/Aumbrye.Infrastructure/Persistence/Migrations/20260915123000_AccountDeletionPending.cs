using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Aumbrye.Infrastructure.Persistence.Migrations;

public partial class AccountDeletionPending : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<bool>(
            name: "DeletionPending",
            table: "Accounts",
            type: "boolean",
            nullable: false,
            defaultValue: false);

        migrationBuilder.CreateIndex(
            name: "IX_Accounts_DeletionPending",
            table: "Accounts",
            column: "DeletionPending");
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropIndex(
            name: "IX_Accounts_DeletionPending",
            table: "Accounts");
        migrationBuilder.DropColumn(name: "DeletionPending", table: "Accounts");
    }
}
