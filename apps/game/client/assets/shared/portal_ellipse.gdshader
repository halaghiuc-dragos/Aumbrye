shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

uniform vec4 color_inner : source_color = vec4(0.55, 0.75, 1.0, 1.0);
uniform vec4 color_outer : source_color = vec4(0.18, 0.28, 0.62, 1.0);
uniform vec4 color_accent : source_color = vec4(0.85, 0.95, 1.0, 1.0);
uniform float pixel_scale : hint_range(4.0, 32.0) = 14.0;
uniform float spin_speed : hint_range(0.0, 6.0) = 2.2;
uniform float spiral_tightness : hint_range(1.0, 12.0) = 5.5;
uniform float ellipse_x : hint_range(0.5, 2.0) = 0.72;
uniform float ellipse_y : hint_range(0.5, 2.0) = 1.0;

float cell_hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 quantize_color(vec3 color, float levels) {
	return floor(color * levels + 0.5) / levels;
}

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	vec2 elliptical = vec2(centered.x / ellipse_x, centered.y / ellipse_y);
	float dist = length(elliptical);
	if (dist > 1.0) {
		discard;
	}

	float angle = atan(elliptical.y, elliptical.x);
	float spiral_phase = angle + dist * spiral_tightness - TIME * spin_speed;
	vec2 spin_dir = vec2(cos(spiral_phase), sin(spiral_phase));
	vec2 pixel_uv = spin_dir * dist * pixel_scale;
	vec2 cell = floor(pixel_uv);

	float grain = cell_hash(cell);
	float ring = fract(dist * 6.0 - TIME * spin_speed * 0.35);
	vec4 col = mix(color_outer, color_inner, grain);
	col = mix(col, color_accent, step(0.82, grain) * (1.0 - dist));
	col = mix(col, color_inner, ring * 0.25);
	col.rgb = quantize_color(col.rgb, 6.0);

	float edge_fade = smoothstep(1.0, 0.82, dist);
	ALBEDO = col.rgb;
	ALPHA = edge_fade;
}
