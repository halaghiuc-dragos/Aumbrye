using Aumbrye.Application.Abstractions;
using Aumbrye.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace Aumbrye.Application.Services;

/// <summary>
/// Persists a strictly ordered, server-observed encounter trail. The player-facing completion
/// endpoint never calls this service: an authoritative session host must emit all four facts.
/// That separation keeps an offline or modified client fail-closed for ranked results.
/// </summary>
public sealed class RankedProgressionObserver(DbContext db) : IRankedProgressionObserver
{
    private static readonly RankedRunMilestoneKind[] RequiredSequence =
    [
        RankedRunMilestoneKind.EncounterStarted,
        RankedRunMilestoneKind.BossDefeated,
        RankedRunMilestoneKind.FinalObjectiveCompleted,
        RankedRunMilestoneKind.Escaped,
    ];

    public async Task<RankedProgressionObservationResult> RecordAuthoritativeMilestoneAsync(
        AuthoritativeRunMilestone milestone,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(milestone.AuthorityId) || milestone.AuthorityId.Length > 128)
            return new RankedProgressionObservationResult(false, Error: "A trusted authority identity is required.");
        if (milestone.Sequence < 1 || milestone.Sequence > RequiredSequence.Length)
            return new RankedProgressionObservationResult(false, Error: "Invalid authoritative milestone sequence.");
        if (RequiredSequence[milestone.Sequence - 1] != milestone.Kind)
            return new RankedProgressionObservationResult(false, Error: "Milestone kind does not match its sequence.");

        var run = await db.Set<Run>()
            .FirstOrDefaultAsync(r => r.Id == milestone.RunId && r.AccountId == milestone.AccountId, ct);
        if (run == null)
            return new RankedProgressionObservationResult(false, Error: "Run not found.");
        if (run.Status != RunStatus.Active)
            return new RankedProgressionObservationResult(false, Error: "Run is no longer active.");
        if (run.Mode != "dungeon" || !run.RankedDefinitionEligible)
            return new RankedProgressionObservationResult(false, Error: "Run is not eligible for ranked observation.");

        var existing = await db.Set<RankedRunMilestone>()
            .Where(x => x.RunId == run.Id)
            .OrderBy(x => x.Sequence)
            .ToListAsync(ct);
        var expectedSequence = existing.Count + 1;
        if (milestone.Sequence != expectedSequence)
        {
            var matching = existing.SingleOrDefault(x => x.Sequence == milestone.Sequence);
            if (matching != null && matching.Kind == milestone.Kind
                && string.Equals(matching.AuthorityId, milestone.AuthorityId, StringComparison.Ordinal))
            {
                return new RankedProgressionObservationResult(true, run.RankedProgressionVerified);
            }
            return new RankedProgressionObservationResult(false, Error: "Authoritative milestones must be observed in order.");
        }

        db.Set<RankedRunMilestone>().Add(new RankedRunMilestone
        {
            Id = Guid.NewGuid(),
            RunId = run.Id,
            AccountId = run.AccountId,
            Sequence = milestone.Sequence,
            Kind = milestone.Kind,
            ObservedAt = DateTimeOffset.UtcNow,
            AuthorityId = milestone.AuthorityId.Trim(),
        });

        var verified = milestone.Kind == RankedRunMilestoneKind.Escaped && existing.Count == RequiredSequence.Length - 1;
        if (verified)
            run.RankedProgressionVerified = true;
        await db.SaveChangesAsync(ct);
        return new RankedProgressionObservationResult(true, verified || run.RankedProgressionVerified);
    }
}
