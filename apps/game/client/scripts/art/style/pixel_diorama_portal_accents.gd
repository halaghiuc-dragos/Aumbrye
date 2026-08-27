extends RefCounted
class_name PixelDioramaPortalAccents


static func add_accents(visuals: Node3D, mats: Dictionary, def: Dictionary) -> void:
	var accents: Array = def.get("accents", [])
	for accent_id in accents:
		match str(accent_id):
			"torch_pair":
				PixelDioramaStyle.add_box(
					visuals,
					Vector3(0.2, 3.0, 0.2),
					Vector3(-2.05, 1.6, 0.15),
					mats.accent,
					"TorchL"
				)
				PixelDioramaStyle.add_box(
					visuals, Vector3(0.2, 3.0, 0.2), Vector3(2.05, 1.6, 0.15), mats.accent, "TorchR"
				)
			"rune_ring":
				var umbral_mat: Material = mats.get("umbral", mats.accent)
				PixelDioramaStyle.add_box(
					visuals,
					Vector3(3.2, 0.18, 0.18),
					Vector3(0.0, 0.2, 0.85),
					umbral_mat,
					"RuneRing"
				)
			"training_torches":
				var training_mat: Material = mats.get("training", mats.accent)
				PixelDioramaStyle.add_box(
					visuals,
					Vector3(0.22, 0.22, 0.22),
					Vector3(-1.0, 0.22, 0.75),
					training_mat,
					"EmberL"
				)
				PixelDioramaStyle.add_box(
					visuals,
					Vector3(0.22, 0.22, 0.22),
					Vector3(1.0, 0.22, 0.75),
					training_mat,
					"EmberR"
				)
				PixelDioramaStyle.add_box(
					visuals,
					Vector3(0.18, 2.8, 0.18),
					Vector3(-2.05, 1.6, 0.12),
					training_mat,
					"TorchL"
				)
				PixelDioramaStyle.add_box(
					visuals,
					Vector3(0.18, 2.8, 0.18),
					Vector3(2.05, 1.6, 0.12),
					training_mat,
					"TorchR"
				)
			"dragon_horns":
				var dragon_mat: Material = mats.get("dragon", mats.accent)
				PixelDioramaStyle.add_box(
					visuals,
					Vector3(0.28, 0.55, 0.28),
					Vector3(-0.62, 4.05, 0.0),
					dragon_mat,
					"HornL"
				)
				PixelDioramaStyle.add_box(
					visuals,
					Vector3(0.28, 0.55, 0.28),
					Vector3(0.62, 4.05, 0.0),
					dragon_mat,
					"HornR"
				)
				PixelDioramaStyle.add_box(
					visuals,
					Vector3(0.85, 0.12, 0.55),
					Vector3(-2.05, 1.9, 0.18),
					dragon_mat,
					"WingL"
				)
				PixelDioramaStyle.add_box(
					visuals,
					Vector3(0.85, 0.12, 0.55),
					Vector3(2.05, 1.9, 0.18),
					dragon_mat,
					"WingR"
				)
				var forge_mat: Material = mats.get("forge", dragon_mat)
				PixelDioramaStyle.add_box(
					visuals,
					Vector3(0.35, 0.35, 0.35),
					Vector3(0.0, 0.28, 0.82),
					forge_mat,
					"DragonEye"
				)
			"cathedral_trim":
				var cathedral_mat: Material = mats.get("cathedral", mats.accent)
				PixelDioramaStyle.add_box(
					visuals,
					Vector3(0.22, 0.75, 0.18),
					Vector3(0.0, 4.05, 0.12),
					cathedral_mat,
					"CrossV"
				)
				PixelDioramaStyle.add_box(
					visuals,
					Vector3(0.65, 0.18, 0.18),
					Vector3(0.0, 4.32, 0.12),
					cathedral_mat,
					"CrossH"
				)
				PixelDioramaStyle.add_box(
					visuals,
					Vector3(0.2, 2.9, 0.2),
					Vector3(-2.05, 1.6, 0.12),
					cathedral_mat,
					"PillarTrimL"
				)
				PixelDioramaStyle.add_box(
					visuals,
					Vector3(0.2, 2.9, 0.2),
					Vector3(2.05, 1.6, 0.12),
					cathedral_mat,
					"PillarTrimR"
				)
