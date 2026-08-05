# Player feedback and loop integrity

Cross-cutting improvements for honesty and feedback. Per-system pages own implementation detail. Conventions: [`../DOC-CONVENTIONS.md`](../DOC-CONVENTIONS.md).

**Companions:** [`../existing_codebase/00-PLACEHOLDER-INVENTORY.md`](../existing_codebase/00-PLACEHOLDER-INVENTORY.md), [`../existing_codebase/00-GAME-LOOP.md`](../existing_codebase/00-GAME-LOOP.md), [`00-QUALITY-BAR.md`](00-QUALITY-BAR.md).

## Today (code)

- Combat skeleton exists (`scripts/combat/`, `scripts/player/`).
- Characters are runtime box assemblies with a procedural pixel filter — not authored art ([`character-authoring.md`](character-authoring.md)).
- Audio often falls back to generators (`audio_director.gd`).
- Affix / quest / results honesty issues are called out in `00-GAME-LOOP.md` with script paths.
- Hub portals and vendors work; Skies/Cathedral portals are hidden (`hub.gd`).

## Change (priority by player impact)

Ordered so each step makes the current loop more honest or more readable before expanding content.

1. **Character silhouettes are real** — replace runtime `BoxMesh` bodies with authored voxel meshes on the existing pivot rig ([`character-authoring.md`](character-authoring.md) CHA-01..CHA-05). Until this lands, every combat and loot improvement is judged against blockout art.
2. **Audio is authored** — replace generator SFX/ambience (`audio_director.gd`) with streams under `assets/audio/`; stop clobbering successful OGG loads via `_restore_generator_streams()` ([`audio-director.md`](audio-director.md)).
3. **Results are honest** — `results_screen.gd` must branch on waves complete/failed keys, not only castle outcomes ([`ui/run_outcome.md`](ui/run_outcome.md)).
4. **Quests are honest** — escape/fetch completion only on real events; wire `register_fetch` from inventory pickup ([`dialogue-quests.md`](dialogue-quests.md), also RFL-01 in [`run-flow.md`](run-flow.md)).
5. **Loot rarity is honest** — `affix_roller.gd` must respect rarity tier tables ([`loot-and-equipment.md`](loot-and-equipment.md)).
6. **Hit confirmation is readable** — reactions target the diorama skin; heal has a dedicated anim/SFX; lunge is non-zero ([`hit-feedback.md`](hit-feedback.md), [`weapons.md`](weapons.md), [`player-heal.md`](player-heal.md)).
7. **UI icons are authored** — replace Unicode/emoji inventory and status cells with `iconPath` / atlas cells ([`ui/inventory_ui.md`](ui/inventory_ui.md), [`ui/status_icon_atlas.md`](ui/status_icon_atlas.md)).
8. **Boss identity matches spawn** — placement IDs vs `get_enemy_id()` mismatches resolved so kill credit and tracking are correct ([`bosses.md`](bosses.md)).
9. **Weapon arts exist** — authored `art` JSON and real lunge motion, only with validation coverage ([`weapons.md`](weapons.md)).

## Out of scope / ABSENT

Do not invent multiplayer, new hub districts, or account meta currencies that have no save/schema/service path today. Online procgen stays behind `USE_ONLINE_PROCgen` until parity suites are green.

## Related

- [`character-authoring.md`](character-authoring.md), [`audio-director.md`](audio-director.md), [`hit-feedback.md`](hit-feedback.md), [`weapons.md`](weapons.md)
- [`ui/inventory_ui.md`](ui/inventory_ui.md), [`ui/run_outcome.md`](ui/run_outcome.md), [`dialogue-quests.md`](dialogue-quests.md)
- [`validation-harness.md`](validation-harness.md)
