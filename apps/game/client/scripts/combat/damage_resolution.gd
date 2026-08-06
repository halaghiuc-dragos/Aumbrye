extends RefCounted
class_name DamageResolution

var incoming: float = 0.0
var outgoing: float = 0.0
var poise_incoming: float = 0.0
var poise_outgoing: float = 0.0
var crit: bool = false
var backstab: bool = false
var blocked: bool = false
var parried: bool = false
var dodged: bool = false
var absorbed_by_poise: bool = false
var damage_type: String = DamageInfo.TYPE_PHYSICAL
var region: String = "body"
var stages: Array[Dictionary] = []
