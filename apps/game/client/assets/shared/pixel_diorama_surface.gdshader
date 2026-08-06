shader_type spatial;
render_mode specular_disabled;

#include "res://assets/shared/pixel_diorama_finish.gdshaderinc"

// surface_kind: 0 = floor, 1 = wall, 2 = prop, 3 = accent
// Floors and walls sample world space so tiling continues across seams; props and
// accents sample object space so the pattern stays locked to moving geometry.

uniform vec4 color_base : source_color = vec4(0.35, 0.32, 0.38, 1.0);
uniform vec4 color_shadow : source_color = vec4(0.25, 0.22, 0.28, 1.0);
uniform vec4 color_accent : source_color = vec4(0.55, 0.42, 0.28, 1.0);
uniform float pixel_scale : hint_range(1.0, 64.0) = 8.0;
uniform float pattern_strength : hint_range(0.0, 1.0) = 0.58;
uniform float stitch_strength : hint_range(0.0, 1.0) = 0.28;
uniform float color_levels : hint_range(4.0, 16.0) = 6.0;
uniform float edge_strength : hint_range(0.0, 1.0) = 0.45;
uniform float shade_bands : hint_range(2.0, 16.0) = 4.0;
uniform float shade_dither : hint_range(0.0, 1.0) = 0.55;
uniform float light_wrap : hint_range(0.0, 1.0) = 0.25;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.08;
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform float dissolve_clip : hint_range(0.0, 1.0) = 1.0;
uniform int surface_kind : hint_range(0, 3) = 0;
uniform bool use_vertex_color = false;
uniform vec3 skin_tint = vec3(1.0);

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec3 v_local_pos;
varying vec3 v_local_normal;

void vertex() {
	v_local_pos = VERTEX;
	v_local_normal = NORMAL;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Authored character meshes supply ARRAY_COLOR per voxel; when use_vertex_color is
// set, skip the procedural prop pattern. Floors and walls still use world-space cells.
const float WORLD_CELL_RATIO = 0.25;

vec2 pattern_coords() {
	if (surface_kind == 0 || surface_kind == 1) {
		return triplanar_pattern_uv(v_world_pos, v_world_normal, pixel_scale * WORLD_CELL_RATIO);
	}
	return triplanar_pattern_uv(v_local_pos, v_local_normal, pixel_scale);
}

vec3 shade_floor(vec2 uv, vec2 cell, float grain, float detail) {
	float checker = mod(cell.x + cell.y, 2.0);
	float mortar = clamp(step(fract(uv.x), 0.06) + step(fract(uv.y), 0.06), 0.0, 1.0);
	vec3 col = mix(color_base.rgb, color_shadow.rgb, checker * pattern_strength * 0.55 * detail);
	col = mix(col, color_shadow.rgb * 0.8, mortar * pattern_strength * 0.6 * detail);
	col = mix(col, color_accent.rgb, step(0.9, grain) * pattern_strength * 0.22 * detail);
	return col;
}

vec3 shade_wall(vec2 uv, float grain, float detail) {
	// Running-bond brick: every other row is offset by half a brick.
	float row = floor(uv.y * 0.5);
	vec2 brick_uv = vec2(uv.x * 0.5 + mod(row, 2.0) * 0.5, uv.y * 0.5);
	vec2 brick_cell = floor(brick_uv);
	float shade = cell_hash(brick_cell);
	float mortar = clamp(step(fract(brick_uv.x), 0.05) + step(fract(brick_uv.y), 0.07), 0.0, 1.0);
	vec3 col = mix(color_base.rgb, color_shadow.rgb, shade * pattern_strength * 0.45 * detail);
	col = mix(col, color_shadow.rgb * 0.7, mortar * pattern_strength * 0.85 * detail);
	col = mix(col, color_accent.rgb, step(0.94, grain) * pattern_strength * 0.16 * detail);
	return col;
}

vec3 shade_prop(vec2 uv, vec2 cell, float grain, float detail) {
	float checker = mod(cell.x + cell.y, 2.0);
	float plank = step(0.72, fract(uv.y * 0.5 + grain * 0.12));
	vec3 col = mix(color_base.rgb, color_shadow.rgb, checker * pattern_strength * 0.4 * detail);
	col = mix(col, color_shadow.rgb * 0.88, plank * pattern_strength * 0.4 * detail);
	col = mix(col, color_accent.rgb, step(0.9, grain) * pattern_strength * 0.22 * detail);
	return col;
}

vec3 shade_accent(vec2 cell, float detail) {
	// Repeating 6-step sparkle, kept from the retired legacy accent shader.
	float sparkle = mod(cell.x * 7.0 + cell.y * 11.0, 6.0);
	vec3 col = color_base.rgb;
	col = mix(col, color_base.rgb * 1.14, step(1.5, sparkle) * step(sparkle, 2.5) * detail);
	col = mix(col, color_accent.rgb, step(4.0, sparkle) * pattern_strength * detail);
	col = mix(col, color_shadow.rgb, step(sparkle, 0.5) * 0.4 * detail);
	return col;
}

void fragment() {
	vec2 uv = pattern_coords();
	vec2 cell = floor(uv);
	float grain = cell_hash(cell);

	// Past a few metres a cell is smaller than a rendered pixel, and the pattern
	// turns into crawling noise. Fade detail out and let the flat palette carry
	// the distance instead.
	float detail = 1.0 - smoothstep(9.0, 26.0, length(VERTEX));

	vec3 col;
	if (use_vertex_color) {
		col = COLOR.rgb * skin_tint;
	} else if (surface_kind == 0) {
		col = shade_floor(uv, cell, grain, detail);
	} else if (surface_kind == 1) {
		col = shade_wall(uv, grain, detail);
	} else if (surface_kind == 2) {
		col = shade_prop(uv, cell, grain, detail);
	} else {
		col = shade_accent(cell, detail);
	}

	float stitch = step(0.9, cell_hash(cell + vec2(3.0, 7.0)));
	col = mix(col, mix(color_shadow.rgb, color_base.rgb, 0.35), stitch * stitch_strength * detail);

	float edge = voxel_edge_mask(uv);
	col = mix(col, color_shadow.rgb * 0.75, edge * edge_strength * detail);

	if (dissolve_clip < 0.999) {
		float dither = cell_hash(floor(v_world_pos.xz * pixel_scale * 0.5));
		if (dither > dissolve_clip) {
			discard;
		}
	}

	// Palette colour lives in albedo; banded light() below supplies tonal steps.
	col = mix(col, vec3(1.0), flash_amount);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	ndl = ndl * (1.0 - light_wrap) + light_wrap;
	float shade = band_light(clamp(ndl * 0.5 + 0.5, 0.0, 1.0), shade_bands, shade_dither, FRAGCOORD.xy);
	float rim = pixel_rim(NORMAL, VIEW, 4.0) * rim_strength;
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * (shade + rim);
}
