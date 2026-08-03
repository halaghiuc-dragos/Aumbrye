shader_type spatial;
render_mode diffuse_toon, specular_disabled;

#include "res://assets/shared/pixel_diorama_finish.gdshaderinc"

uniform int pattern_type = 0;
uniform vec4 base_color : source_color = vec4(0.35, 0.32, 0.38, 1.0);
uniform vec4 mid_color : source_color = vec4(0.42, 0.38, 0.45, 1.0);
uniform vec4 dark_color : source_color = vec4(0.18, 0.16, 0.22, 1.0);
uniform vec4 accent_color : source_color = vec4(0.55, 0.42, 0.28, 1.0);
uniform float pixel_scale = 7.5;
uniform float color_levels : hint_range(4.0, 16.0) = 6.0;
uniform float edge_strength : hint_range(0.0, 1.0) = 0.42;
uniform float stitch_strength : hint_range(0.0, 1.0) = 0.28;
uniform float pattern_strength : hint_range(0.0, 1.0) = 0.58;

vec4 apply_voxel_finish(vec4 col, vec2 uv, vec2 cell) {
	float edge = voxel_edge_mask(uv);
	col = mix(col, dark_color, edge * edge_strength);

	float stitch = step(0.9, cell_hash(cell + vec2(3.0, 7.0)));
	col = mix(col, mix(dark_color, mid_color, 0.35), stitch * stitch_strength);

	vec3 finished = apply_portal_finish(col.rgb, uv, accent_color.rgb, pixel_scale, pattern_strength);
	col.rgb = quantize_color(finished, color_levels);
	return col;
}

vec4 sample_floor(vec2 uv) {
	vec2 cell = floor(uv);
	float checker = mod(cell.x + cell.y, 2.0);
	float mortar = step(fract(uv.x), 0.09) + step(fract(uv.y), 0.09);
	mortar = clamp(mortar, 0.0, 1.0);
	vec4 col = mix(base_color, mid_color, checker);
	col = mix(col, dark_color, mortar * 0.75);
	float grain = step(0.82, cell_hash(cell));
	col = mix(col, accent_color, grain * 0.12);
	return apply_voxel_finish(col, uv, cell);
}

vec4 sample_wall(vec2 uv) {
	float row = floor(uv.y);
	float offset = mod(row, 2.0) * 0.5;
	vec2 buv = vec2(uv.x + offset, uv.y);
	vec2 cell = floor(buv);
	float brick = mod(cell.x + cell.y, 2.0);
	float mortar = step(fract(buv.x), 0.08) + step(fract(uv.y), 0.1);
	mortar = clamp(mortar, 0.0, 1.0);
	vec4 col = mix(base_color, mid_color, brick);
	col = mix(col, dark_color, mortar * 0.8);
	float weave = step(0.86, cell_hash(cell * 1.7));
	col = mix(col, dark_color * 0.92, weave * 0.18);
	return apply_voxel_finish(col, buv, cell);
}

vec4 sample_accent(vec2 uv) {
	vec2 cell = floor(uv);
	float sparkle = mod(cell.x * 7.0 + cell.y * 11.0, 6.0);
	vec4 col = base_color;
	col = mix(col, mid_color, step(1.5, sparkle) * step(sparkle, 2.5));
	col = mix(col, accent_color, step(4.0, sparkle));
	col = mix(col, dark_color, step(sparkle, 0.5) * 0.4);
	return apply_voxel_finish(col, uv, cell);
}

void fragment() {
	vec2 uv = UV * pixel_scale;
	vec4 col = base_color;
	if (pattern_type == 0) {
		col = sample_floor(uv);
	} else if (pattern_type == 1) {
		col = sample_wall(uv);
	} else {
		col = sample_accent(uv);
	}
	ALBEDO = col.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
