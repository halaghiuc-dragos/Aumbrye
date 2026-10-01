extends Node3D
class_name BiomePropKitPiece

## One piece of a biome's prop kit. The model is a Blender build (tools/blender/props_biome.py)
## chosen by the biome's style and this piece's kind; the biome's palette colours it. The scene
## around it carries only what the model cannot: a collision body for pieces you walk into.

@export var biome_id: String = ""
@export var piece_kind: String = "pillar"  # pillar | sconce | rubble_a | rubble_b | statue | altar | banner | debris_pile


func _ready() -> void:
	PropLibrary.attach(self, PropLibrary.biome_prop_id(biome_id, piece_kind), biome_id)
