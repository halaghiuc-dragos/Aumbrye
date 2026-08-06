using Aumbrye.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Aumbrye.Infrastructure.Persistence.Migrations;

[DbContext(typeof(AumbryeDbContext))]
[Migration("20260805120002_AddAccountDisplayNameAndTokenFamily")]
public partial class AddAccountDisplayNameAndTokenFamily
{
}
