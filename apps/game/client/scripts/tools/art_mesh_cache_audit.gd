extends Node

const SkinScript := preload("res://scripts/art/characters/diorama_character_skin.gd")
const VoxelMeshBuilderScript := preload("res://scripts/art/characters/voxel_mesh_builder.gd")
const PixelStyleScript := preload("res://scripts/art/style/pixel_diorama_style.gd")
const MAX_CACHE_ENTRIES := 256

var _failures := 0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("Art mesh cache audit: %s" % label)


func _ready() -> void:
	SkinScript._kit_mesh_cache.clear()
	SkinScript._kit_mesh_cache_order.clear()
	SkinScript._kit_mesh_cache_hits = 0
	SkinScript._kit_mesh_cache_misses = 0
	SkinScript._kit_mesh_cache_evictions = 0
	SkinScript._kit_mesh_cache_peak = 0
	var vis := {"cache_key": "freshness-audit"}
	var base := {"edge": 0.5, "snapToTheme": false, "palette": [[0.8, 0.2, 0.2]], "cells": [[0, 0, 0]]}
	var first := SkinScript._kit_mesh(vis, base, PixelDioramaStyle.PaletteTheme.CASTLE, false)
	var reused := SkinScript._kit_mesh(vis, base.duplicate(true), PixelDioramaStyle.PaletteTheme.CASTLE, false)
	_check(first == reused, "identical voxel source and palette reuse the retained mesh")
	var changed_voxels: Dictionary = base.duplicate(true)
	changed_voxels["cells"] = [[0, 0, 0], [1, 0, 0]]
	var changed_mesh := SkinScript._kit_mesh(vis, changed_voxels, PixelDioramaStyle.PaletteTheme.CASTLE, false)
	_check(changed_mesh != first, "changed source voxels invalidate an identical authored cache label")
	var changed_palette: Dictionary = base.duplicate(true)
	changed_palette["palette"] = [[0.1, 0.8, 0.3]]
	var palette_mesh := SkinScript._kit_mesh(vis, changed_palette, PixelDioramaStyle.PaletteTheme.CASTLE, false)
	_check(palette_mesh != first, "changed source palette invalidates the cached mesh")
	var themed_mesh := SkinScript._kit_mesh(vis, base, PixelDioramaStyle.PaletteTheme.CRYSTAL, false)
	_check(themed_mesh != first, "theme palette is part of runtime mesh cache identity")
	var mirrored_mesh := SkinScript._kit_mesh(vis, base, PixelDioramaStyle.PaletteTheme.CASTLE, true)
	_check(mirrored_mesh != first, "mirrored mesh variant has an independent cache identity")
	for variant_index in MAX_CACHE_ENTRIES + 12:
		var variant: Dictionary = base.duplicate(true)
		variant["cells"] = [[variant_index, 0, 0]]
		SkinScript._kit_mesh(vis, variant, variant_index % 10, false)
	var stats: Dictionary = SkinScript.get_kit_mesh_cache_stats()
	var authored_path := "res://assets/characters/player_warden/armr.voxels.json"
	var loaded_once := VoxelMeshBuilderScript.load_mesh(authored_path, PixelDioramaStyle.PaletteTheme.CASTLE)
	var loaded_twice := VoxelMeshBuilderScript.load_mesh(authored_path, PixelDioramaStyle.PaletteTheme.CASTLE)
	var builder_stats: Dictionary = VoxelMeshBuilderScript.get_cache_stats()
	_check(loaded_once != null and loaded_once == loaded_twice, "authored file mesh loads reuse its content-fingerprinted cache entry")
	_check(int(builder_stats.get("retained", 0)) <= int(builder_stats.get("limit", 0)), "file-backed mesh cache reports a bounded retained set")
	PixelStyleScript._bevel_mesh_cache.clear()
	PixelStyleScript._bevel_mesh_cache_order.clear()
	PixelStyleScript._bevel_mesh_cache_hits = 0
	PixelStyleScript._bevel_mesh_cache_misses = 0
	PixelStyleScript._bevel_mesh_cache_evictions = 0
	PixelStyleScript._bevel_mesh_cache_peak = 0
	var first_bevel := PixelStyleScript.bevel_box_mesh(Vector3(0.8, 1.0, 1.2), 0.1)
	var reused_bevel := PixelStyleScript.bevel_box_mesh(Vector3(0.8, 1.0, 1.2), 0.1)
	_check(first_bevel == reused_bevel, "identical bevel dimensions reuse one mesh")
	for variant_index in MAX_CACHE_ENTRIES + 12:
		PixelStyleScript.bevel_box_mesh(
			Vector3(0.8 + float(variant_index) * 0.1, 1.0, 1.2), 0.1
		)
	for theme_index in 10:
		var theme: int = theme_index
		PixelStyleScript.make_floor_material(theme)
		PixelStyleScript.make_wall_material(theme)
		PixelStyleScript.make_prop_material(theme)
		PixelStyleScript.make_accent_material(theme)
		PixelStyleScript.make_emissive_material(theme)
	var art_stats: Dictionary = PixelStyleScript.get_art_cache_stats()
	var bevel_stats: Dictionary = art_stats.get("bevel_meshes", {})
	var material_stats: Dictionary = art_stats.get("materials", {})
	_check(int(bevel_stats.get("retained", 0)) <= int(bevel_stats.get("limit", 0)), "procedural bevel cache retains no more than its configured bound")
	_check(int(bevel_stats.get("peak", 0)) <= int(bevel_stats.get("limit", 0)) and int(bevel_stats.get("evictions", 0)) > 0, "procedural bevel churn records a bounded peak and evictions")
	_check(int(material_stats.get("surface", 0)) >= 20 and int(material_stats.get("accent", 0)) >= 10 and int(material_stats.get("emissive", 0)) >= 10, "material cache statistics include all exercised biome theme families")
	_check(int(stats.get("retained", 0)) <= MAX_CACHE_ENTRIES, "customization churn keeps retained meshes bounded")
	_check(int(stats.get("peak", 0)) <= MAX_CACHE_ENTRIES, "mesh cache peak never exceeds its configured bound")
	_check(int(stats.get("evictions", 0)) >= 1, "old cache variants are evicted when the limit is reached")
	_check(int(stats.get("hits", 0)) >= 1 and int(stats.get("misses", 0)) > MAX_CACHE_ENTRIES, "cache reports actual hit and rebuild activity")
	print("ART MESH CACHE STATS %s" % JSON.stringify(stats))
	print("ART FILE MESH CACHE STATS %s" % JSON.stringify(builder_stats))
	print("ART STYLE CACHE STATS %s" % JSON.stringify(art_stats))
	print("ART MESH CACHE RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
