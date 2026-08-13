namespace Aumbrye.Api;

public static class ProblemResults
{
    public static IResult BadRequest(string detail) =>
        Results.Problem(detail: detail, statusCode: StatusCodes.Status400BadRequest);

    public static IResult Unauthorized(string detail) =>
        Results.Problem(detail: detail, statusCode: StatusCodes.Status401Unauthorized);

    public static IResult Forbidden(string detail) =>
        Results.Problem(detail: detail, statusCode: StatusCodes.Status403Forbidden);

    public static IResult NotFound(string detail) =>
        Results.Problem(detail: detail, statusCode: StatusCodes.Status404NotFound);

    public static IResult Conflict(string detail) =>
        Results.Problem(detail: detail, statusCode: StatusCodes.Status409Conflict);

    public static IResult PayloadTooLarge(string detail) =>
        Results.Problem(detail: detail, statusCode: StatusCodes.Status413PayloadTooLarge);

    /// <summary>Well-formed request the server understood but refuses to act on (e.g. a corrupt save).</summary>
    public static IResult UnprocessableEntity(string detail) =>
        Results.Problem(detail: detail, statusCode: StatusCodes.Status422UnprocessableEntity);

    public static IResult ServiceUnavailable(string detail) =>
        Results.Problem(detail: detail, statusCode: StatusCodes.Status503ServiceUnavailable);

    public static IResult InternalError(string detail) =>
        Results.Problem(detail: detail, statusCode: StatusCodes.Status500InternalServerError);
}
