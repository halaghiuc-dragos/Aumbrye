shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque;

// RM-07: a translucent, scrolling-noise barrier plane for a fog gate -- the boss door and a
// lock-in arena's doorways use this so "sealed" reads as a wall of hostile light, not a box.

uniform vec4 tint : source_color = vec4(0.55, 0.4, 0.85, 0.55);
uniform float scroll_speed : hint_range(0.0, 3.0) = 0.4;
uniform float noise_scale : hint_range(1.0, 32.0) = 6.0;
uniform float alpha_base : hint_range(0.0, 1.0) = 0.35;
uniform float alpha_variance : hint_range(0.0, 1.0) = 0.3;
uniform float emission_energy : hint_range(0.0, 4.0) = 0.6;

float _hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float _noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = _hash(i);
	float b = _hash(i + vec2(1.0, 0.0));
	float c = _hash(i + vec2(0.0, 1.0));
	float d = _hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

void fragment() {
	vec2 uv = UV * noise_scale;
	uv.y -= TIME * scroll_speed;
	float n = _noise(uv) * 0.6 + _noise(uv * 2.3 + 5.0) * 0.4;
	ALBEDO = tint.rgb;
	ALPHA = clamp(alpha_base + n * alpha_variance, 0.0, 1.0) * tint.a;
	EMISSION = tint.rgb * emission_energy;
}
