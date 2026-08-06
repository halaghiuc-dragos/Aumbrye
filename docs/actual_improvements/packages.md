# Packages — improvement plan

## Status: FINISHED

## Current state

`Aumbrye.Procedural` and `Aumbrye.Shared` share typed dungeon definitions, leaderboard DTOs, Swashbuckle-generated OpenAPI with CI drift checks, checksum-returning serialization, and strict Release builds. See [`../existing_codebase/packages.md`](../existing_codebase/packages.md).

## Gaps

| ID | Sev | Gap | Status |
|----|-----|-----|--------|
| PKG-01 | P0 | Leaderboards absent from OpenAPI | **FINISHED** — routes in `aumbrye-api.v1.yaml` |
| PKG-02 | P0 | `SubmitLeaderboardRequest` not in shared | **FINISHED** — `Contracts/Leaderboards/` |
| PKG-03 | P1 | Untyped `RoomContent`/`Locks`/`Puzzles` | **FINISHED** — `RoomContentEntry`, typed records |
| PKG-04 | P1 | Dead DTO fields | **FINISHED** — `RunResultRequest` removed; `CharacterStateJson`, `Conflict` populated |
| PKG-05 | P1 | OpenAPI missing 200 response schemas | **FINISHED** — `.Produces<T>` on all routes |
| PKG-06 | P1 | No spec drift check | **FINISHED** — CI `swagger tofile` + diff |
| PKG-07 | P2 | `ExtractChecksum` string scan | **FINISHED** — `Serialize` returns checksum tuple |
| PKG-08 | P2 | Unrelated version constants | **FINISHED** — `ProceduralAssembly.Version` → `ApiVersions` |
| PKG-09 | P2 | `ContentPaths` opaque failure | **FINISHED** — actionable `AUMBRYE_CONTENT_ROOT` message |
| PKG-10 | P2 | Silent analyzer warnings | **FINISHED** — `TreatWarningsAsErrors` on both csprojs |

## Target design

**The OpenAPI document is generated from the running API, not hand-written.** Add Swashbuckle to `Aumbrye.Api`, annotate every endpoint with `.Produces<T>(statusCode)` and `.ProducesProblem(statusCode)`, and add a CI step that boots the API in the `Testing` environment, dumps `swagger.json`, converts it to YAML, and fails if it differs from `packages/shared/openapi/aumbrye-api.v1.yaml`. This makes PKG-01, PKG-05, and PKG-06 structurally impossible to reintroduce. Rejected alternative: keeping the hand-written spec and adding a review checklist — it already drifted by two endpoints, so process is not the fix.

**Target endpoint annotations** (applied in `services/backend/src/Aumbrye.Api/Endpoints/`):

| Route | Produces |
|-------|----------|
| `GET /api/v1/health` | `200 HealthResponse` |
| `POST /api/v1/auth/register` | `200 AuthResponse`, `400 ErrorResponse`, `429` |
| `POST /api/v1/auth/login` | `200 AuthResponse`, `401 ErrorResponse`, `429` |
| `POST /api/v1/auth/refresh` | `200 AuthResponse`, `401 ErrorResponse`, `429` |
| `POST /api/v1/runs` | `200 CreateRunResponse`, `400 ErrorResponse`, `401`, `500 ErrorResponse` |
| `GET /api/v1/runs/{id}/dungeon` | `200 application/json` (raw `DungeonDefinition`), `401`, `404` |
| `POST /api/v1/runs/{id}/complete` | `200 CompleteRunResponse`, `400 ErrorResponse`, `401` |
| `GET /api/v1/saves/current` | `200 SaveResponse`, `400 ErrorResponse`, `401` |
| `PUT /api/v1/saves/current` | `200 PutSaveResponse`, `400 ErrorResponse`, `401`, `409 SaveConflictResponse` |
| `GET /api/v1/leaderboards` | `200 LeaderboardPageResponse` |
| `POST /api/v1/leaderboards/submit` | `200 SubmitLeaderboardResponse`, `401` |

**New shared DTOs** in `packages/shared/Contracts/`:

```csharp
// Contracts/ErrorResponse.cs
public sealed record ErrorResponse(string Error);

// Contracts/Leaderboards/LeaderboardContracts.cs
public sealed record SubmitLeaderboardRequest(string BiomeId, int Tier, double ElapsedSeconds, bool OptIn);
public sealed record SubmitLeaderboardResponse(bool Submitted, string? Reason = null);
public sealed record LeaderboardEntryResponse(Guid AccountId, string DisplayName, double ElapsedSeconds, DateTimeOffset SubmittedAt);
public sealed record LeaderboardPageResponse(string BiomeId, int Tier, IReadOnlyList<LeaderboardEntryResponse> Entries);

// Contracts/Saves/SaveContracts.cs (added)
public sealed record SaveConflictResponse(string Error, string State, DateTimeOffset UpdatedAt);
```

`SubmitLeaderboardRequest` moves out of `LeaderboardsEndpoints.cs:54` and the endpoint returns the typed records instead of anonymous objects.

**Typed room content in `DungeonDefinition`.** Replace the three `IReadOnlyList<object>?` fields with real records mirroring what the GDScript generator emits (see [`../existing_codebase/room-content.md`](../existing_codebase/room-content.md) for the authoritative shape):

```csharp
public sealed record RoomContentEntry(string RoomId, string ContentType, IReadOnlyDictionary<string, JsonElement> Params);
public sealed record DungeonLock(string RoomId, string LockId, string KeyItemId);
public sealed record DungeonPuzzle(string RoomId, string PuzzleId, string Kind);
```

`DungeonPlacements.Puzzles` becomes `IReadOnlyList<DungeonPuzzle>`. `CanonicalJsonSerializer` gains three sorted-dictionary builders so ordering stays deterministic. `RoomTypeAssigner` populates `RoomContent`; until it does, the fields stay empty but are now *typed* empty, which lets `cross_stack_parity_suite.gd` assert on shape.

**Dead DTO resolution.** Delete `RunResultRequest`. Populate `CompleteRunProgressionResponse.CharacterStateJson` from the saved state in `RunService.CompleteRunAsync` (it already serializes `stateJson` at `services/backend/src/Aumbrye.Application/Services/RunService.cs:189`). Return `PutSaveResponse` with `Conflict = true` plus a `SaveConflictResponse` body from the 409 path.

**Content root diagnostics.** `ContentPaths.FindContentRoot` throws a message naming the directories it searched and the `AUMBRYE_CONTENT_ROOT` override:

```
Could not locate content/ directory. Searched upward from '<BaseDirectory>'.
Set AUMBRYE_CONTENT_ROOT to an absolute path containing biomes/, enemies/, items/.
```

## Work plan

1. **Add `ErrorResponse` and the leaderboard contracts to `packages/shared`** — new `Contracts/ErrorResponse.cs` and `Contracts/Leaderboards/LeaderboardContracts.cs`; add `SaveConflictResponse` to `Contracts/Saves/SaveContracts.cs`. Delete `RunResultRequest` from `Contracts/Runs/RunContracts.cs:39-46`. (PKG-02, PKG-04)
2. **Switch the API to typed responses** — `LeaderboardsEndpoints.cs` returns `LeaderboardPageResponse` and `SubmitLeaderboardResponse`; `ApiEndpoints.cs` returns `ErrorResponse` instead of `new { error = ... }` and `SaveConflictResponse` for 409; `PutSaveResponse` gets `Conflict` set. (PKG-02, PKG-04)
3. **Populate `CharacterStateJson`** — thread the serialized state from `RunService.CompleteRunAsync` (`RunService.cs:189`) into `RunProgressionResult`, and set it on the response in `ApiEndpoints.cs:125-137`. (PKG-04)
4. **Add Swashbuckle and `.Produces<T>` annotations** — `Swashbuckle.AspNetCore` package reference in `Aumbrye.Api.csproj`; `AddSwaggerGen` and `UseSwagger` in `Program.cs`; annotate all 11 routes per the table above. (PKG-05, PKG-06)
5. **Add the spec-drift CI step** — new step in the `backend` job of `.github/workflows/ci.yml` that runs `dotnet swagger tofile --yaml --output /tmp/spec.yaml <api.dll> v1` and `diff /tmp/spec.yaml packages/shared/openapi/aumbrye-api.v1.yaml`. Non-zero diff fails the job. Regenerate and commit the spec as part of this step's landing. (PKG-01, PKG-06)
6. **Type `RoomContent`, `Locks`, `Puzzles`** — new records in `Models/DungeonDefinition.cs`, matching builders in `Serialization/CanonicalJsonSerializer.cs`, and update `content/schemas/dungeon-definition.v1.json`. Generation still emits empty lists; the change is shape-only and leaves both stacks runnable. (PKG-03)
7. **Return the checksum directly** — change `CanonicalJsonSerializer.Serialize` to return `(string Json, string Checksum)` and delete `DungeonGenerator.ExtractChecksum`. (PKG-07)
8. **Single version constant** — delete `ProceduralAssembly.Version` and have callers read `ApiVersions.ExpectedClientVersion`, or make `ProceduralAssembly.Version => ApiVersions.ExpectedClientVersion`. Add a unit test asserting the Godot `ApiConfig.CLIENT_VERSION` string matches. (PKG-08)
9. **Improve `ContentPaths` diagnostics** — rewrite the throw at `Content/ContentPaths.cs:30` with the message above. (PKG-09)
10. **Tighten build settings** — add `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>`, `<AnalysisLevel>latest-recommended</AnalysisLevel>`, `<EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>` to both csproj files, then fix the resulting warnings. Land last so earlier steps are not blocked. (PKG-10)

## Data and schema changes

- `content/schemas/dungeon-definition.v1.json` gains typed `roomContent`, `locks`, and `placements.puzzles` array item schemas matching the new records. Validate against `content/fixtures/dungeon_definition*.json` via `scripts/validate-content/validate.mjs:70`.
- No `user://` save-format change, so **no `save_migrator.gd` version bump**.
- `packages/shared/openapi/aumbrye-api.v1.yaml` is regenerated, not hand-edited, after step 5.

## Acceptance criteria

- [x] `packages/shared/openapi/aumbrye-api.v1.yaml` lists all 11 routes the API maps, including both leaderboards routes.
- [x] Every operation in the spec declares a response schema for its 200 case.
- [x] The `backend` CI job fails if the generated spec differs from the committed one.
- [x] `SubmitLeaderboardRequest` is declared in `packages/shared/Contracts/Leaderboards/`, and `LeaderboardsEndpoints.cs` contains no record declarations.
- [x] `grep -r "RunResultRequest" packages services apps` returns no matches.
- [x] A successful `POST /api/v1/runs/{id}/complete` response body contains a non-null `characterStateJson`.
- [x] A 409 from `PUT /api/v1/saves/current` deserializes into `SaveConflictResponse` with non-empty `state`.
- [x] `DungeonDefinition.RoomContent` is `IReadOnlyList<RoomContentEntry>`, and `content/schemas/dungeon-definition.v1.json` validates the shape.
- [x] `CanonicalJsonSerializer.Serialize` returns the checksum; `ExtractChecksum` no longer exists.
- [x] `dotnet build Aumbrye.sln --configuration Release` emits zero warnings.

## Validation

Backend, under `services/backend/tests/Aumbrye.UnitTests/`:

- Extend `ProceduralAssemblyTests.cs` with `Version_MatchesApiExpectedClientVersion`.
- New `CanonicalJsonSerializerTests.cs`: `Serialize_ReturnsChecksumMatchingRecomputedHash`, `Serialize_IsByteIdenticalForSameDefinition`, `Serialize_SortsKeysOrdinally`.
- Extend `DungeonSeedDeriverTests.cs` with `GenerationSeed_Tier1Floor1_EqualsBaseSeed` and `GenerationSeed_IsStableAcrossProcesses` (assert against a hardcoded expected value).
- New `ContentPathsTests.cs`: `FindContentRoot_ThrowsWithActionableMessage_WhenAbsent` using a temp `AppContext.BaseDirectory`.

Backend, under `services/backend/tests/Aumbrye.IntegrationTests/`:

- New `LeaderboardsIntegrationTests.cs`: `Submit_OptOut_ReturnsSubmittedFalse`, `Submit_Unauthenticated_Returns401`, `Get_ReturnsSubmittedEntryOrderedByElapsed`, `Get_UnknownBiome_ReturnsEmptyEntries`.
- New `OpenApiContractTests.cs`: fetch `/swagger/v1/swagger.json` from the test host and assert every path in the committed YAML is present, and vice versa.

Client, under `apps/game/client/scripts/validation/suites/`:

- Extend `cross_stack_parity_suite.gd` with `cross_stack.room_content_shape`, asserting that `content/schemas/dungeon-definition.v1.json` declares typed `roomContent` items rather than a bare array, so PKG-03 cannot silently regress.

## Related

- Existing behavior: [`../existing_codebase/packages.md`](../existing_codebase/packages.md)
- [`backend-api.md`](backend-api.md) — endpoint-side work for PKG-02 and PKG-04
- [`website-and-backend.md`](website-and-backend.md) — the OpenAPI contract consumers
- [`local-procgen.md`](local-procgen.md), [`room-content.md`](room-content.md) — the GDScript shape PKG-03 must mirror
- [`ci-cd.md`](ci-cd.md) — the spec-drift job
