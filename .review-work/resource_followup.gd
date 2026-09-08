extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var stamina = load("res://scripts/combat/stamina.gd").new()
	stamina.configure(10.0)
	stamina.consume(10.0)
	for i in range(100):
		stamina._physics_process(0.1)
	print("RESOURCE_CHECK low_max current=", stamina.current, " max=", stamina.max_stamina, " exhausted=", stamina.is_exhausted(), " can_spend_one=", stamina.has(1.0))
	stamina.reset_stamina()
	stamina.consume(-5.0)
	print("RESOURCE_CHECK negative_cost current=", stamina.current, " max=", stamina.max_stamina)
	var mana = load("res://scripts/combat/mana.gd").new()
	mana.current = 3.0
	var drained = mana.drain(5.0)
	print("RESOURCE_CHECK mana_drain success=", drained, " remaining=", mana.current)
	var poise = load("res://scripts/combat/poise.gd").new()
	poise.take_poise_damage(50.0)
	poise.configure(50.0)
	print("RESOURCE_CHECK poise_reconfigure broken=", poise.is_broken(), " execution_available=", poise.execution_available)
	stamina.free()
	mana.free()
	poise.free()
	quit()
