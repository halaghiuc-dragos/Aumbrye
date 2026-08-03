shader_type spatial;
render_mode diffuse_burley, specular_disabled;

#include "res://assets/shared/pixel_diorama_finish.gdshaderinc"

uniform vec4 color_base : source_color = vec4(0.35, 0.32, 0.38, 1.0);
uniform vec4 color_shadow : source_color = vec4(0.25, 0.22, 0.28, 1.0);
uniform vec4 color_accent : source_color = vec4(0.55, 0.42, 0.28, 1.0);
uniform float pixel_scale : hint_range(1.0, 64.0) = 8.0;
uniform float pattern_strength : hint_range(0.0, 1.0) = 0.58;
uniform float color_levels : hint_range(4.0, 16.0) = 6.0;
uniform float edge_strength : hint_range(0.0, 1.0) = 0.45;
uniform int surface_kind : hint_range(0, 2) = 0;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 pattern_uv;
	if (surface_kind == 0) {
		pattern_uv = v_world_pos.xz * pixel_scale;
	} else if (surface_kind == 1) {
		pattern_uv = vec2(v_world_pos.x + v_world_pos.z, v_world_pos.y) * pixel_scale * 0.55;
	} else {
		pattern_uv = UV * pixel_scale;
	}

	vec2 cell = floor(pattern_uv);
	float checker = mod(cell.x + cell.y, 2.0);
	float grain = cell_hash(cell);
	float band = step(0.7, fract(cell.y * 0.35 + grain * 0.15));
	float stitch = step(0.88, cell_hash(cell + vec2(5.0, 13.0)));

	vec3 col = mix(color_base.rgb, color_shadow.rgb, checker * pattern_strength);
	col = mix(col, color_shadow.rgb * 0.88, band * pattern_strength * 0.7);
	col = mix(col, color_accent.rgb, step(0.86, grain) * pattern_strength * 0.38);
	col = mix(col, color_shadow.rgb * 0.82, stitch * pattern_strength * 0.32);

	float edge = voxel_edge_mask(pattern_uv);
	col = mix(col, color_shadow.rgb * 0.72, edge * edge_strength);

	col = apply_portal_finish(col, pattern_uv, color_accent.rgb, pixel_scale, pattern_strength);

	float facing = abs(dot(normalize(v_world_normal), vec3(0.0, 1.0, 0.0)));
	if (surface_kind == 1) {
		col *= mix(0.86, 1.06, facing);
	} else if (surface_kind == 2) {
		col *= mix(0.92, 1.02, facing);
	}

	ALBEDO = quantize_color(col, color_levels);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
