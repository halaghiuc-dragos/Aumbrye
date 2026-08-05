class_name RoomContentTypes
extends RefCounted

const COMBAT := "combat"
const EMPTY := "empty"
const TRAP := "trap"
const HAZARD := "hazard"
const PUZZLE := "puzzle"
const NPC_QUEST := "npc_quest"
const LOCKED_VAULT := "locked_vault"
const BOSS := "boss"
const REWARD := "reward"
const STAIRS := "stairs"

const REST := "rest"
const LORE := "lore"
const MERCHANT := "merchant"

const TEMPLATE_BY_TYPE := {
	TRAP: "trap_spike_pack",
	HAZARD: "hazard_poison_zone",
	PUZZLE: "puzzle_lever_gate",
	NPC_QUEST: "npc_quest_giver",
	LOCKED_VAULT: "locked_vault_chest",
	REWARD: "reward_cache",
	REST: "rest_bonfire",
	LORE: "lore_readable",
	MERCHANT: "dungeon_merchant",
}
