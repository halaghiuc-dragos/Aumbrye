using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Aumbrye.Infrastructure.Persistence.Migrations;

public partial class AddAccountSteamId : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AlterColumn<string>(
            name: "Email",
            table: "Accounts",
            type: "character varying(256)",
            maxLength: 256,
            nullable: true,
            oldClrType: typeof(string),
            oldType: "character varying(256)",
            oldMaxLength: 256);

        migrationBuilder.DropIndex(
            name: "IX_Accounts_Email",
            table: "Accounts");

        migrationBuilder.AddColumn<ulong>(
            name: "SteamId",
            table: "Accounts",
            type: "bigint",
            nullable: true);

        migrationBuilder.AddColumn<DateTimeOffset>(
            name: "SteamLinkedAt",
            table: "Accounts",
            type: "timestamp with time zone",
            nullable: true);

        migrationBuilder.CreateIndex(
            name: "IX_Accounts_Email",
            table: "Accounts",
            column: "Email",
            unique: true,
            filter: "\"Email\" IS NOT NULL");

        migrationBuilder.CreateIndex(
            name: "IX_Accounts_SteamId",
            table: "Accounts",
            column: "SteamId",
            unique: true,
            filter: "\"SteamId\" IS NOT NULL");
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropIndex(
            name: "IX_Accounts_SteamId",
            table: "Accounts");

        migrationBuilder.DropIndex(
            name: "IX_Accounts_Email",
            table: "Accounts");

        migrationBuilder.DropColumn(
            name: "SteamLinkedAt",
            table: "Accounts");

        migrationBuilder.DropColumn(
            name: "SteamId",
            table: "Accounts");

        migrationBuilder.AlterColumn<string>(
            name: "Email",
            table: "Accounts",
            type: "character varying(256)",
            maxLength: 256,
            nullable: false,
            defaultValue: "",
            oldClrType: typeof(string),
            oldType: "character varying(256)",
            oldMaxLength: 256,
            oldNullable: true);

        migrationBuilder.CreateIndex(
            name: "IX_Accounts_Email",
            table: "Accounts",
            column: "Email",
            unique: true);
    }
}
