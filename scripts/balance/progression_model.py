"""How many clears of a tier does it take to be ready for the next one?

The difficulty ladder is authored as two multipliers per tier (`hpMult`, `damageMult`) and the
player's answer to them is authored somewhere else entirely — the loot tables, the talent tree and
the class rating scale. Nothing connected the two, so "is tier 2 a wall or a formality?" could only
be answered by playing it.

This model connects them. It is deliberately coarse: it does not simulate combat, positioning or
skill, and it is not trying to predict a real player's experience. What it does do is put the
supply of power and the demand for power in the same units, so a change to either can be checked
against the other.

    demand(t)  = hpMult(t) * damageMult(t)

        Enemy health scales the time a kill takes; enemy damage scales the rate you lose health.
        A player needs the product of the two more attrition capacity than they needed at tier 1.

    supply(n)  = effective_hp * dps, relative to a fresh warden

        after n clears, from talent points earned and the best-in-slot gear the loot tables are
        expected to have produced by then.

The number that matters is `clears_needed`, the smallest n where supply(n) >= demand(t). A tier
that wants 0 is a formality; a tier that wants more than about 6 is a wall.

Usage:  python scripts/balance/progression_model.py [--tier N] [--dungeon ID] [--trials N]
"""

from __future__ import annotations

import argparse
import collections
import glob
import json
import pathlib
import random
import statistics

ROOT = pathlib.Path(__file__).resolve().parents[2]

#: Power weight per unit of a stat, used to collapse an item's stat block into one number. These
#: are the same relative values the class rating units are built on: one point of armour is worth
#: about 2.5 health, one percent of crit about 0.8 health, and so on.
STAT_WEIGHT = {
    "maxHealth": 1.0,
    "healthRegen": 4.0,
    "defense": 2.5,
    "armor": 2.5,
    "evasion": 1.5,
    "damagePercent": 2.0,
    "bonusDamage": 2.0,
    "critChance": 80.0,
    "poise": 1.0,
    "staminaMax": 0.6,
    "staminaRegen": 25.0,
    "staminaCostReduction": 40.0,
    "moveSpeed": 100.0,
    "moveSpeedPercent": 1.5,
    "blockReduction": 60.0,
    "damageReduction": 100.0,
    "poiseDamage": 25.0,
    "manaMax": 0.4,
    "manaRegen": 15.0,
    "cooldownReduction": 30.0,
    "lootQuality": 0.0,
    "xpGain": 0.0,
    "goldFind": 0.0,
}

EQUIP_SLOTS = ("helmet", "chest", "gloves", "boots", "weapon", "secondary", "ring", "amulet")

#: A tier-1 clear is roughly this many kills plus the boss, which is what the xp curve is fed.
KILLS_PER_CLEAR = 30
#: Equipment drops a clear is expected to yield across treasure, side and boss rooms.
DROPS_PER_CLEAR = 5
#: One talent point buys about this much of one stat, so about this much total power.
POWER_PER_TALENT_POINT = 0.035


def load_json(path):
    return json.loads(pathlib.Path(path).read_text(encoding="utf-8"))


def item_power(stats: dict) -> float:
    return sum(
        STAT_WEIGHT.get(k, 1.0) * float(v)
        for k, v in stats.items()
        if isinstance(v, (int, float))
    )


def load_items() -> dict:
    items = {}
    for f in glob.glob(str(ROOT / "content/items/**/*.json"), recursive=True):
        data = load_json(f)
        candidates = data if isinstance(data, list) else data.get("items", [data])
        for it in candidates:
            if not isinstance(it, dict) or "id" not in it:
                continue
            items[it["id"]] = {
                "slot": it.get("equipmentSlot") or it.get("slot") or "",
                "type": it.get("itemType", ""),
                "rarity": it.get("rarity", "common"),
                "power": item_power(it.get("stats", {}) or {}),
            }
    return items


def load_drop_pool(items: dict, dungeon_id: str) -> list:
    """Equipment drops a run can produce, as (itemId, weight) weighted by the loot tables.

    `dungeon_id` of "all" unions every dungeon's tables. That is the honest pool for the upper
    rungs: difficulty tiers inside one dungeon climb to 10, and a player that high has unlocked
    most of the depth ladder and is wearing what it dropped. Reading one dungeon's table alone
    makes the loot supply look like it saturates when really the player has moved on.
    """
    if dungeon_id == "all":
        paths = sorted(glob.glob(str(ROOT / "content/loot/tables/*.json")))
    else:
        paths = [str(ROOT / f"content/loot/tables/{dungeon_id}.json")]
    pool = []
    for path in paths:
        if not pathlib.Path(path).exists():
            continue
        tables = load_json(path).get("lootTables", {})
        for entries in tables.values():
            for entry in entries:
                item_id = entry.get("itemId", "")
                info = items.get(item_id)
                if info is None or info["slot"] not in EQUIP_SLOTS:
                    continue
                pool.append((item_id, float(entry.get("weight", 1)), info))
    return pool


def talent_points_after(xp_curve: dict, clears: int) -> int:
    per_clear = KILLS_PER_CLEAR * float(xp_curve.get("baseXpPerKill", 25)) + float(
        xp_curve.get("bossBonusXp", 150)
    )
    total_xp = per_clear * clears
    level = 1
    for entry in xp_curve.get("levels", []):
        if total_xp >= float(entry.get("xpRequired", 0)):
            level = int(entry.get("level", 1))
    return (level - 1) * int(xp_curve.get("talentPointsPerLevel", 1))


def run_career(
    pool: list, tiers: list, base_power: float, xp_curve: dict, rng: random.Random, cap: int
) -> list:
    """One simulated career: clear each tier until the next one is beatable, and record how often.

    Modelling a single tier's loot in isolation understates the supply badly, because a tier's
    `lootBonus` is exactly the game's answer to its own `hpMult` — the rung that is harder also
    pays better. A career walks the ladder the way a player does, farming the highest tier it has
    actually beaten.
    """
    weights = [w for _, w, _ in pool]
    best = collections.defaultdict(float)
    clears_total = 0
    result = []
    for index, tier in enumerate(tiers[:-1]):
        loot_bonus = float(tier.get("lootBonus", 0.0))
        demand = float(tiers[index + 1].get("hpMult", 1.0)) * float(
            tiers[index + 1].get("damageMult", 1.0)
        )
        clears_here = 0
        while clears_here < cap:
            for _ in range(DROPS_PER_CLEAR):
                _, _, info = rng.choices(pool, weights=weights, k=1)[0]
                # A tier's loot bonus raises the quality of what it drops, which is the supply
                # side of the same knob that raised its difficulty.
                best[info["slot"]] = max(best[info["slot"]], info["power"] * (1.0 + loot_bonus))
            clears_here += 1
            clears_total += 1
            points = talent_points_after(xp_curve, clears_total)
            if supply(base_power, sum(best.values()), points) >= demand:
                break
        result.append(
            {
                "from_tier": int(tier.get("tier", index + 1)),
                "to_tier": int(tiers[index + 1].get("tier", index + 2)),
                "demand": demand,
                "clears": clears_here,
                "capped": clears_here >= cap,
            }
        )
    return result


def supply(base_power: float, gear_power: float, talent_points: int) -> float:
    """Power relative to a fresh warden with starting gear and no talents."""
    gear_factor = (base_power + gear_power) / base_power
    talent_factor = 1.0 + POWER_PER_TALENT_POINT * talent_points
    return gear_factor * talent_factor


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dungeon", default="forgotten_castle", help="dungeon whose ladder to model")
    ap.add_argument("--trials", type=int, default=400)
    ap.add_argument("--max-clears", type=int, default=12)
    ap.add_argument(
        "--target",
        default="2-5",
        help="acceptable clears needed to reach tier 2, as LOW-HIGH",
    )
    args = ap.parse_args()
    rng = random.Random(20260813)

    items = load_items()
    xp_curve = load_json(ROOT / "content/progression/xp_curve.json")
    # Every dungeon shares one difficulty ladder, so "all" can borrow the first one's tiers.
    ladder_id = args.dungeon if args.dungeon != "all" else "forgotten_castle"
    dungeon = load_json(ROOT / f"content/dungeons/{ladder_id}.json")
    tiers = dungeon.get("difficultyTiers", dungeon.get("tiers", []))
    pool = load_drop_pool(items, args.dungeon)

    # A fresh warden's power baseline: the standard rating-10 stat line, collapsed with the same
    # weights the items use, so gear and character sit in one scale.
    class_defs = [load_json(f) for f in glob.glob(str(ROOT / "content/classes/*.json"))]
    standard = {}
    for stat in class_defs[0]["statRatings"]:
        standard[stat] = statistics.mean(float(c["statBonuses"][stat]) for c in class_defs)
    base_power = 100.0 + item_power(standard)

    print(f"dungeon        {args.dungeon}")
    print(f"drop pool      {len(pool)} equippable entries")
    print(f"base power     {base_power:.1f}  (fresh warden, average class)")
    print()

    careers = [
        run_career(pool, tiers, base_power, xp_curve, rng, args.max_clears)
        for _ in range(args.trials)
    ]

    low, high = (int(x) for x in args.target.split("-"))
    problems = []
    print(
        f"{'step':>9} {'demand':>7} {'median':>7} {'unlucky':>8} {'lucky':>6}  clears of the lower tier"
    )
    for i in range(len(careers[0])):
        rows = [c[i] for c in careers]
        counts = sorted(r["clears"] for r in rows)
        median = statistics.median(counts)
        unlucky = counts[int(len(counts) * 0.9)]
        lucky = counts[int(len(counts) * 0.1)]
        step = f"t{rows[0]['from_tier']}->t{rows[0]['to_tier']}"
        capped = sum(1 for r in rows if r["capped"])
        note = f"  ({capped} of {len(rows)} hit the {args.max_clears} cap)" if capped else ""
        print(
            f"{step:>9} {rows[0]['demand']:>7.2f} {median:>7.1f} {unlucky:>8} {lucky:>6}{note}"
        )
        if rows[0]["to_tier"] == 2 and not (low <= median <= high):
            problems.append(
                f"tier 2 takes a median {median:.1f} clears of tier 1, wanted {low}-{high}"
            )
        if capped > len(rows) * 0.1:
            problems.append(
                f"{step} stalls: {capped} of {len(rows)} careers never got there within "
                f"{args.max_clears} clears - demand outruns what the loot can supply"
            )
    print()
    for p in problems:
        print("PROBLEM", p)
    if not problems:
        print(f"every rung is climbable and tier 2 sits inside the {args.target} clear window")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
