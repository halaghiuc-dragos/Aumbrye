using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Aumbrye.Infrastructure.Persistence.Migrations;

public partial class AddAccountDisplayNameAndTokenFamily : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<string>(
            name: "DisplayName",
            table: "Accounts",
            type: "character varying(32)",
            maxLength: 32,
            nullable: false,
            defaultValue: "");

        migrationBuilder.Sql(
            """
            UPDATE "Accounts"
            SET "DisplayName" = 'Wanderer-' || left(replace("Id"::text, '-', ''), 6)
            WHERE "DisplayName" = '';
            """);

        migrationBuilder.CreateIndex(
            name: "IX_Accounts_DisplayName",
            table: "Accounts",
            column: "DisplayName",
            unique: true);

        migrationBuilder.AddColumn<Guid>(
            name: "FamilyId",
            table: "RefreshTokens",
            type: "uuid",
            nullable: false,
            defaultValue: Guid.Empty);

        migrationBuilder.Sql(
            """
            UPDATE "RefreshTokens"
            SET "FamilyId" = "Id"
            WHERE "FamilyId" = '00000000-0000-0000-0000-000000000000';
            """);

        migrationBuilder.AddColumn<string>(
            name: "ReplacedByTokenHash",
            table: "RefreshTokens",
            type: "character varying(128)",
            maxLength: 128,
            nullable: true);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropIndex(name: "IX_Accounts_DisplayName", table: "Accounts");
        migrationBuilder.DropColumn(name: "DisplayName", table: "Accounts");
        migrationBuilder.DropColumn(name: "FamilyId", table: "RefreshTokens");
        migrationBuilder.DropColumn(name: "ReplacedByTokenHash", table: "RefreshTokens");
    }
}
