using System.Security.Claims;

namespace Aumbrye.Api.Auth;

public static class ClaimsPrincipalExtensions
{
    public static Guid? AccountId(this ClaimsPrincipal user)
    {
        var id = user.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(id, out var guid) ? guid : null;
    }
}
