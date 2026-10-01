extends Control


signal offer_closed(relic_id: String)

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")
const OFFER_COUNT := 3
## Wide and tall enough for a full flavour line plus a multi-rule stat breakdown without either
## wrapping onto itself or getting clipped by the panel around it -- most relics carry a rule.
const CARD_MIN_SIZE := Vector2(320.0, 360.0)

## Same colours the gear-comparison tooltip already uses for "this stat got better/worse" --
## a relic offer is exactly that question asked once, up front, so it reads the same way.
const COLOR_GIVES := "#7fd67f"
const COLOR_TAKES := "#e07a7a"

## The label for a rule's trigger, from `RELIC_EVENT_<EVENT>`; an event without one shows its id.
func _event_label(event: String) -> String:
	var key := "RELIC_EVENT_" + event.to_upper()
	var label := tr(key)
	return event if label == key else label

var _open := false
var _offer_ids: Array[String] = []
var _buttons: Array[Button] = []


func _ready() -> void:
	add_to_group("relic_offer_ui")
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_open() -> bool:
	return _open


func open_offer(offer_key: String) -> bool:
	if _open or RunBuffs == null:
		return false
	var rolled: Array[String] = RunBuffs.roll_offer(offer_key, OFFER_COUNT)
	if rolled.is_empty():
		return false
	_offer_ids = rolled
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	MenuStack.push(self, true)
	_build_ui()
	return true


func _build_ui() -> void:
	var shell: Dictionary = MenuShellScript.build_modal(
		self,
		tr("RELIC_OFFER_TITLE"),
		GameUISkinScript.MENU_HALF_W + 280.0,
		GameUISkinScript.MENU_HALF_H + 210.0
	)
	var vbox: VBoxContainer = shell["content_vbox"]
	MenuShellScript.add_subtitle(vbox, tr("RELIC_OFFER_SUBTITLE"))
	var row := HBoxContainer.new()
	row.name = "OfferRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", GameUISkinScript.PIXEL_UNIT * 4)
	vbox.add_child(row)
	_buttons.clear()
	for relic_id in _offer_ids:
		row.add_child(_make_card(relic_id))
	MenuShellScript.add_hint(vbox, tr("RELIC_OFFER_HINT"))
	_wire_focus_ring()
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func _make_card(relic_id: String) -> Control:
	var def := RelicCatalog.get_definition(relic_id)
	var card := VBoxContainer.new()
	card.name = "Card_%s" % relic_id
	card.custom_minimum_size = CARD_MIN_SIZE
	card.add_theme_constant_override("separation", GameUISkinScript.PIXEL_UNIT)

	var name_label := Label.new()
	name_label.text = str(def.get("name", relic_id))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(name_label)

	# The prose in `description` is shown too. The colour-coded stat breakdown below is the thing a
	# run-paced decision needs, but a relic offer is also the one moment the game stops to hand the
	# player an object with a history to it, and without that line every relic would feel like a stat
	# stick with no world behind it. Shown in the hint style (dim, small) so it reads as flavour, not as
	# another number.
	var flavor := ContentText.description(def)
	if flavor != "":
		var flavor_label := Label.new()
		flavor_label.text = flavor
		flavor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		flavor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		GameUISkinScript.style_hint_label(flavor_label)
		card.add_child(flavor_label)

	var relevance := RunBuffs.offer_relevance(relic_id) if RunBuffs else {}
	var missing: Array = relevance.get("missingStatuses", []) as Array
	var missing_names: Array[String] = []
	for status_id in missing:
		var id := str(status_id)
		missing_names.append(ContentText.name(StatusCatalog.get_definition(id), id))
	if not missing_names.is_empty():
		var future_label := Label.new()
		future_label.text = tr("RELIC_OFFER_FUTURE_BUILD").format({"statuses": ", ".join(missing_names)})
		future_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		future_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		GameUISkinScript.style_hint_label(future_label)
		card.add_child(future_label)
	elif not (relevance.get("requiredStatuses", []) as Array).is_empty():
		var ready_label := Label.new()
		ready_label.text = tr("RELIC_OFFER_READY_NOW")
		ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		GameUISkinScript.style_hint_label(ready_label)
		card.add_child(ready_label)

	var family_matches: Array[String] = RunBuffs.offer_family_matches(relic_id) if RunBuffs else []
	if not family_matches.is_empty():
		var synergy_label := Label.new()
		var labels: Array[String] = []
		for family in family_matches:
			labels.append(family.capitalize())
		synergy_label.text = tr("RELIC_OFFER_BUILD_SYNERGY") % " • ".join(labels)
		synergy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		synergy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		synergy_label.add_theme_color_override("font_color", Color(COLOR_GIVES))
		card.add_child(synergy_label)

	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.text = _describe(def)
	card.add_child(body)

	var take := MenuShellScript.make_menu_button(
		tr("RELIC_OFFER_TAKE"), func() -> void: _take(relic_id)
	)
	card.add_child(take)
	_buttons.append(take)
	return card


## What the relic actually gives and takes, in that order, colour-coded the same way a gear
## comparison is: green for a stat that helps you, red for one that costs you. The prose
## `description` still exists in the data (it is what NPC dialogue and encyclopaedia text quote),
## but a shopping decision made at a run's pace needs this to be readable in a glance, not a
## paragraph.
func _describe(def: Dictionary) -> String:
	var gives: PackedStringArray = []
	var takes: PackedStringArray = []
	var stats: Dictionary = def.get("stats", {})
	for stat in stats:
		var value := float(stats[stat])
		if is_zero_approx(value):
			continue
		var line := Equipment.format_stat_line(str(stat), value)
		if value > 0.0:
			gives.append(line)
		else:
			takes.append(line)
	for rule in def.get("rules", []):
		if rule is Dictionary:
			gives.append(_describe_rule(rule as Dictionary))
	var lines: PackedStringArray = []
	for line in gives:
		lines.append("[color=%s]%s[/color]" % [COLOR_GIVES, line])
	for line in takes:
		lines.append("[color=%s]%s[/color]" % [COLOR_TAKES, line])
	return "\n".join(lines)


## Every rule effect the shared combat dispatcher (`combat_events.gd`) knows how to apply is a
## benefit, so a rule line is always green -- the schema has no "cost" effect, only "cost" stats.
func _describe_rule(rule: Dictionary) -> String:
	var event := str(rule.get("event", ""))
	var trigger := _event_label(event)
	var body := _describe_effect(rule)
	var qualifiers: PackedStringArray = []
	var chance := float(rule.get("chance", 1.0))
	if chance > 0.0 and chance < 1.0:
		qualifiers.append(tr("RELIC_QUAL_CHANCE") % roundi(chance * 100.0))
	var if_damage := str(rule.get("ifDamageType", ""))
	if if_damage != "":
		qualifiers.append(tr("RELIC_QUAL_DAMAGE") % if_damage.capitalize())
	var if_status := str(rule.get("ifTargetHasStatus", ""))
	if if_status != "":
		qualifiers.append(tr("RELIC_QUAL_TARGET") % if_status.capitalize())
	var cooldown := float(rule.get("cooldown", 0.0))
	if cooldown > 0.0:
		qualifiers.append(tr("RELIC_QUAL_COOLDOWN") % _compact_num(cooldown))
	var reset_on: Array = rule.get("resetOn", [])
	if not reset_on.is_empty():
		var reset_triggers: PackedStringArray = []
		for reset_event in reset_on:
			reset_triggers.append(_event_label(str(reset_event)))
		qualifiers.append(tr("RELIC_QUAL_RESETS") % " / ".join(reset_triggers))
	var suffix := " (%s)" % ", ".join(qualifiers) if not qualifiers.is_empty() else ""
	return "%s: %s%s" % [trigger, body, suffix]


## GDScript's `%` string operator has no `%g`, so a whole-number float like a 6-second cooldown
## would otherwise print as "6.000000" -- this drops the decimal only when there is nothing after
## it to lose.
func _compact_num(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(round(value)))
	return "%.1f" % value


func _describe_effect(rule: Dictionary) -> String:
	var amount := float(rule.get("amount", 0.0))
	match str(rule.get("effect", "")):
		"restore_stamina":
			return tr("RELIC_EFFECT_STAMINA") % int(amount)
		"restore_health":
			return tr("RELIC_EFFECT_HEALTH") % int(amount)
		"restore_mana":
			return tr("RELIC_EFFECT_MANA") % int(amount)
		"lifesteal":
			var pct := float(rule.get("pct", 0.0))
			return tr("RELIC_EFFECT_LIFESTEAL_PCT") % roundi(pct * 100.0) if pct > 0.0 else tr("RELIC_EFFECT_LIFESTEAL")
		"apply_status":
			var stacks := int(rule.get("stacks", 1))
			var status_id := str(rule.get("statusId", "")).capitalize()
			return tr("RELIC_EFFECT_APPLY") % [status_id, (" x%d" % stacks) if stacks > 1 else ""]
		"spread_status":
			var radius := float(rule.get("radius", 0.0))
			var spread_status_id := str(rule.get("statusId", "")).capitalize()
			return tr("RELIC_EFFECT_SPREAD") % [spread_status_id, _compact_num(radius)]
		"add_stack":
			var per_stack := float(rule.get("perStack", 0.0))
			var stat_id := str(rule.get("stat", ""))
			var max_stacks := int(rule.get("maxStacks", 1))
			return tr("RELIC_EFFECT_STACKS") % [
				Equipment.format_stat_value(stat_id, per_stack, true), max_stacks
			]
		"bonus_gold":
			return tr("RELIC_EFFECT_GOLD") % int(amount)
		"refund_flask":
			var flasks := maxi(1, int(amount))
			return (tr("RELIC_EFFECT_FLASK_ONE") if flasks == 1 else tr("RELIC_EFFECT_FLASK_MANY")) % flasks
		"clear_status":
			return (
				tr("RELIC_EFFECT_CLEAR_ALL")
				if str(rule.get("removalPolicy", "debuffs")) == "all"
				else tr("RELIC_EFFECT_CLEANSE")
			)
		_:
			return str(rule.get("effect", ""))


func _take(relic_id: String) -> void:
	if not _open:
		return
	if RunBuffs and RunBuffs.take_offer(relic_id):
		_close(relic_id)


func _close(relic_id: String) -> void:
	if not _open:
		return
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStack.pop(self)
	_buttons.clear()
	_offer_ids.clear()
	offer_closed.emit(relic_id)


func _wire_focus_ring() -> void:
	if _buttons.is_empty():
		return
	for i in _buttons.size():
		var btn := _buttons[i]
		var prev := _buttons[(i - 1 + _buttons.size()) % _buttons.size()]
		var next := _buttons[(i + 1) % _buttons.size()]
		btn.focus_neighbor_left = prev.get_path()
		btn.focus_neighbor_right = next.get_path()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
