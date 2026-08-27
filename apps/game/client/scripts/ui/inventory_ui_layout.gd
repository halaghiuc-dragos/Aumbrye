class_name InventoryUILayout
extends RefCounted


const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

const CELL_SIZE := GameUISkinScript.INVENTORY_CELL_SIZE
const EQUIP_CELL_SIZE := GameUISkinScript.INVENTORY_EQUIP_CELL_SIZE
const GRID_GAP := GameUISkinScript.GRID_GAP

const EQUIP_LAYOUT: Array = [
	["", "helmet", ""],
	["weapon", "chest", "secondary"],
	["gloves", "amulet", "ring"],
	["", "boots", "relic"],
]

const SLOT_LABELS: Dictionary = {
	"helmet": "Head",
	"chest": "Chest",
	"gloves": "Hands",
	"boots": "Feet",
	"weapon": "Main",
	"secondary": "Off",
	"ring": "Ring",
	"amulet": "Neck",
	"relic": "Relic",
}
