# Phase M7 — EA Polish and Steam Ship

- **phase:** M7
- **goal:** Public Early Access on Steam Windows meeting DoD.
- **depends_on:** M6 exit criteria
- **exit_criteria:**
  - [ ] All boxes in [07-EA-DEFINITION-OF-DONE.md](../07-EA-DEFINITION-OF-DONE.md) checked
  - [ ] Steam depot builds installable
  - [ ] ≥20 external playtesters completed full loop — [MANUAL_PLAYTEST_CHECKLIST.md](../../design/MANUAL_PLAYTEST_CHECKLIST.md) § M7
  - [ ] All M7 feel/UX items in [MANUAL_PLAYTEST_CHECKLIST.md](../../design/MANUAL_PLAYTEST_CHECKLIST.md) § M7 checked
  - [ ] Crash rate acceptable (define threshold in playtest notes)
  - [ ] Known issues published

---

## Minor milestones

### STEAM-7.1 — Steamworks client init

- **status:** not_started
- **depends_on:** [M6]
- **unlocks:** [STEAM-7.2, STEAM-7.3]
- **primary_paths:**
  - `apps/game/client/` Steam integration (GodotSteam or equivalent)
- **agent_instructions:**
  - Initialize Steam API; ownership check; overlay works in dev app id.
- **acceptance_criteria:**
  - [ ] Game launches via Steam
  - [ ] Overlay opens
- **out_of_scope:**
  - Deck verification official

### STEAM-7.2 — Achievements sync

- **status:** not_started
- **depends_on:** [STEAM-7.1, META-6.1]
- **unlocks:** []
- **agent_instructions:**
  - Mirror server achievements to Steam achievements.
- **acceptance_criteria:**
  - [ ] Unlock appears in Steam
- **out_of_scope:**
  - Stats API beyond needs

### STEAM-7.3 — Cloud saves bridge

- **status:** not_started
- **depends_on:** [STEAM-7.1, SAVE-4.1]
- **unlocks:** []
- **agent_instructions:**
  - Steam Cloud and/or continue backend cloud as source of truth; document policy.
- **acceptance_criteria:**
  - [ ] Save survives reinstall via chosen cloud path
- **out_of_scope:**
  - Cross-platform cloud conflicts fancy UI

### STEAM-7.4 — Auth ticket to backend (if needed)

- **status:** not_started
- **depends_on:** [STEAM-7.1, AUTH-3.1]
- **unlocks:** []
- **agent_instructions:**
  - Optional: exchange Steam session ticket for JWT. If deferred, document.
- **acceptance_criteria:**
  - [ ] Implemented OR listed as known limitation with email auth still working
- **out_of_scope:**
  - Forcing Steam-only accounts

### POLISH-7.1 — Controller glyph pass

- **status:** not_started
- **depends_on:** [A11Y-6.1]
- **unlocks:** []
- **agent_instructions:**
  - Dynamic glyphs for Xbox/PlayStation/generic; UI focus states polished.
- **acceptance_criteria:**
  - [ ] Full loop completable gamepad-only without mouse — see [MANUAL_PLAYTEST_CHECKLIST.md](../../design/MANUAL_PLAYTEST_CHECKLIST.md) § M7 (Controller)
- **out_of_scope:**
  - Gyro

### POLISH-7.2 — Tutorial / first-run guidance

- **status:** not_started
- **depends_on:** [HUB-4.1]
- **unlocks:** []
- **agent_instructions:**
  - Optional training prompts; do not kill discovery; hub tips.
- **acceptance_criteria:**
  - [ ] New player can learn roll/parry in arena
  - [ ] Can skip tips
- **out_of_scope:**
  - Mandatory 30-minute tutorial

### PERF-7.1 — Optimization sprint

- **status:** not_started
- **depends_on:** [PERF-6.1]
- **unlocks:** []
- **agent_instructions:**
  - Profile GPU/CPU; fix top offenders; LOD/occlusion/pooling as needed.
- **acceptance_criteria:**
  - [ ] Meet 1080p 60 min; document 144 aspire results
- **out_of_scope:**
  - RTGI experiments

### PERF-7.2 — Stability: logging + crash hooks

- **status:** not_started
- **depends_on:** []
- **unlocks:** []
- **agent_instructions:**
  - Structured logs; crash report path; content version in reports.
- **acceptance_criteria:**
  - [ ] Crashes produce actionable reports in playtest
- **out_of_scope:**
  - Full SaaS APM mandatory spend

### SCHEMA-7.1 — Save migration matrix

- **status:** not_started
- **depends_on:** [SAVE-4.1]
- **unlocks:** []
- **primary_paths:**
  - `docs/SAVE_MIGRATIONS.md`
- **agent_instructions:**
  - Document migration from each schemaVersion; implement needed migrators.
- **acceptance_criteria:**
  - [ ] Old M4 sample save migrates or fails with clear message
- **out_of_scope:**
  - Infinite backward compat

### SHIP-7.1 — Closed playtest

- **status:** not_started
- **depends_on:** [STEAM-7.1, PERF-7.1, POLISH-7.1]
- **unlocks:** [SHIP-7.2]
- **agent_instructions:**
  - Recruit ≥20 playtesters; collect feedback form; triage P0/P1.
  - Use [MANUAL_PLAYTEST_CHECKLIST.md](../../design/MANUAL_PLAYTEST_CHECKLIST.md) sign-off table.
- **acceptance_criteria:**
  - [ ] 20 completed loop
  - [ ] P0 list empty
- **out_of_scope:**
  - Ignoring combat feedback

### SHIP-7.2 — Store page + trailer capture

- **status:** not_started
- **depends_on:** [THEME-6.2]
- **unlocks:** [SHIP-7.3]
- **agent_instructions:**
  - Capsule, screenshots, trailer, EA description, known issues.
- **acceptance_criteria:**
  - [ ] Store assets checklist complete
- **out_of_scope:**
  - Influencer seeding plan mandatory

### SHIP-7.3 — Release candidate + EA launch

- **status:** not_started
- **depends_on:** [SHIP-7.1, SHIP-7.2, DoD]
- **unlocks:** []
- **agent_instructions:**
  - Tag `ea-1.0.0`; build depots; set live; monitor day-one crashes.
  - Verify [07-EA-DEFINITION-OF-DONE.md](../07-EA-DEFINITION-OF-DONE.md).
- **acceptance_criteria:**
  - [ ] Public Steam branch live
  - [ ] Hotfix process documented
- **out_of_scope:**
  - Launch party features

### CI-7.1 — Release workflow

- **status:** not_started
- **depends_on:** [CI-0.2]
- **unlocks:** []
- **agent_instructions:**
  - Tagged build workflow for API docker image + web deploy + Godot export artifact.
- **acceptance_criteria:**
  - [ ] Tag triggers release artifacts
- **out_of_scope:**
  - Auto Steam upload without human confirm

---

## Inherited from M4 (deferred)

| Item | M7 milestone | Notes |
| ---- | ------------ | ----- |
| Gamepad-only full loop | `POLISH-7.1` | Structural controller nav done in M4; feel gate manual — [MANUAL_PLAYTEST_CHECKLIST.md](../../design/MANUAL_PLAYTEST_CHECKLIST.md) |
| Cloud save E2E (second device/session) | `STEAM-7.3` | Backend `GET/PUT /saves/current` live; multi-session verify before EA |
| TEST-4.1 ten-run soak | Manual § M4 | Can complete during M7 polish — [m4_soak_notes.md](../../design/m4_soak_notes.md) |

---

## M7 ordered work queue

1. STEAM-7.1 → 7.2/7.3/7.4
2. POLISH-7.1 + POLISH-7.2
3. PERF-7.1 + PERF-7.2 + SCHEMA-7.1
4. CI-7.1
5. SHIP-7.1 → SHIP-7.2 → SHIP-7.3
6. Final DoD audit
