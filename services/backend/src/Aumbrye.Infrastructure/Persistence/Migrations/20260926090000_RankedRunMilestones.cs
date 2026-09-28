using Aumbrye.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Aumbrye.Infrastructure.Persistence.Migrations;

[DbContext(typeof(AumbryeDbContext))]
[Migration("20260926090000_RankedRunMilestones")]
public partial class RankedRunMilestones : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(
            name: "RankedRunMilestones",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                RunId = table.Column<Guid>(type: "uuid", nullable: false),
                AccountId = table.Column<Guid>(type: "uuid", nullable: false),
                Sequence = table.Column<int>(type: "integer", nullable: false),
                Kind = table.Column<int>(type: "integer", nullable: false),
                ObservedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                AuthorityId = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_RankedRunMilestones", x => x.Id);
                table.ForeignKey(
                    name: "FK_RankedRunMilestones_Runs_RunId",
                    column: x => x.RunId,
                    principalTable: "Runs",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });
        migrationBuilder.CreateIndex(
            name: "IX_RankedRunMilestones_RunId_Kind",
            table: "RankedRunMilestones",
            columns: new[] { "RunId", "Kind" },
            unique: true);
        migrationBuilder.CreateIndex(
            name: "IX_RankedRunMilestones_RunId_Sequence",
            table: "RankedRunMilestones",
            columns: new[] { "RunId", "Sequence" },
            unique: true);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(name: "RankedRunMilestones");
    }
}
