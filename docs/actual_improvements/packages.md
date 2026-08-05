# Packages — improvement plan

## Current state

`Aumbrye.Procedural` is a complete, deterministic dungeon generator with SplitMix64 seeding, canonical key-sorted JSON, SHA-256 checksums, and v5-UUID loot instance IDs (see [`../existing_codebase/packages.md`](../existing_codebase/packages.md)). `Aumbrye.Shared` holds the API DTOs and the OpenAPI 3.0.3 spec. The weak points are contract drift rather than generation logic: the leaderboards endpoints exist on the API but are missing from both the OpenAPI spec and `packages/shared/Contracts`, three declared DTO fields are never populated, and `DungeonDefinition.RoomContent`/`Locks`/`Puzzles` are permanently empty arrays that the GDScript stack does populate.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| PKG-01 | P0 | Leaderboards are absent from the OpenAPI spec. Two live endpoints have no contract, so no consumer can be generated and no reviewer can see the shape. | `packages/shared/openapi/aumbrye-api.v1.yaml:8-150` lists 7 paths; `services/backend/src/Aumbrye.Api/Endpoints/LeaderboardsEndpoints.cs:11,35` maps two more |
| PKG-02 | P0 | `SubmitLeaderboardRequest` lives in the API assembly, not `packages/shared`. It is the only request DTO not shareable with clients. | `services/backend/src/Aumbrye.Api/Endpoints/LeaderboardsEndpoints.cs:54-58` |
| PKG-03 | P1 | `DungeonDefinition.RoomContent`, `Locks`, and `Puzzles` are hardcoded to `Array.Empty<object>()`, and `DungeonPlacements.Puzzles` is an untyped `IReadOnlyList<object>`. The C# stack cannot express room content that the GDScript generator produces, so cross-stack parity is structurally impossible for those keys. | `packages/procedural/Generation/DungeonGenerator.cs:122-124`, `packages/procedural/Models/DungeonDefinition.cs:16-18,35` |
| PKG-04 | P1 | Three declared DTO fields are dead: `RunResultRequest` (no reference anywhere), `CompleteRunProgressionResponse.CharacterStateJson` (never set), `PutSaveResponse.Conflict` (never set — the 409 path returns an anonymous object). Clients reading the DTO see fields that never arrive. | `packages/shared/Contracts/Runs/RunContracts.cs:29,39-46`, `packages/shared/Contracts/Saves/SaveContracts.cs:13` vs `services/backend/src/Aumbrye.Api/Endpoints/ApiEndpoints.cs:125-137,197-208` |
| PKG-05 | P1 | The OpenAPI spec documents response bodies for exactly one operation. Six operations state only a status code and a prose description, so a generated client would produce `object` return types. | `packages/shared/openapi/aumbrye-api.v1.yaml:24-119` versus `:126-131` |
| PKG-06 | P1 | Nothing verifies that the OpenAPI spec matches the routes the API actually maps. The spec is hand-written and already 2 paths behind. | No Swashbuckle/NSwag document generation; `Program.cs:46` registers `AddEndpointsApiExplorer` but no generator |
| PKG-07 | P2 | `ExtractChecksum` re-scans the serialized JSON string for a `"checksum":"` literal instead of returning the value `CanonicalJsonSerializer.Serialize` already computed. Any future key named `checksum` inside a nested object would be matched first. | `packages/procedural/Generation/DungeonGenerator.cs:130-139` |
| PKG-08 | P2 | `ProceduralAssembly.Version = "0.3.0"` and `ApiVersions.ExpectedClientVersion = "0.3.0"` are unrelated constants that must be bumped together by hand. | `packages/procedural/ProceduralAssembly.cs:8`, `packages/shared/Contracts/ApiVersions.cs:7` |
| PKG-09 | P2 | `ContentPaths.Root` is a static property evaluated once per process and throws if `content/` is not found. A published CLI or containerized API without a sibling `content/` fails at first catalog access with no actionable message about `AUMBRYE_CONTENT_ROOT`. | `packages/procedural/Content/ContentPaths.cs:5,30` |
| PKG-10 | P2 | Neither csproj sets `TreatWarningsAsErrors`, `AnalysisLevel`, or `EnforceCodeStyleInBuild`, so nullable and analyzer warnings accumulate silently through `dotnet build --configuration Release`. | `packages/procedural/Aumbrye.Procedural.csproj:3-8`, `packages/shared/Aumbrye.Shared.csproj:3-8` |

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

- [ ] `packages/shared/openapi/aumbrye-api.v1.yaml` lists all 11 routes the API maps, including both leaderboards routes.
- [ ] Every operation in the spec declares a response schema for its 200 case.
- [ ] The `backend` CI job fails if the generated spec differs from the committed one.
- [ ] `SubmitLeaderboardRequest` is declared in `packages/shared/Contracts/Leaderboards/`, and `LeaderboardsEndpoints.cs` contains no record declarations.
- [ ] `grep -r "RunResultRequest" packages services apps` returns no matches.
- [ ] A successful `POST /api/v1/runs/{id}/complete` response body contains a non-null `characterStateJson`.
- [ ] A 409 from `PUT /api/v1/saves/current` deserializes into `SaveConflictResponse` with non-empty `state`.
- [ ] `DungeonDefinition.RoomContent` is `IReadOnlyList<RoomContentEntry>`, and `content/schemas/dungeon-definition.v1.json` validates the shape.
- [ ] `CanonicalJsonSerializer.Serialize` returns the checksum; `ExtractChecksum` no longer exists.
- [ ] `dotnet build Aumbrye.sln --configuration Release` emits zero warnings.

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
