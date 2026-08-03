// Shared pixel-diorama finish: portal-style grain, rings, and quantization.

float cell_hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 quantize_color(vec3 color, float levels) {
	return floor(color * levels + 0.5) / levels;
}

float voxel_edge_mask(vec2 uv) {
	float edge_x = min(fract(uv.x), 1.0 - fract(uv.x));
	float edge_y = min(fract(uv.y), 1.0 - fract(uv.y));
	float edge = step(edge_x, 0.11) + step(edge_y, 0.11);
	return clamp(edge, 0.0, 1.0);
}

// Static spiral pixel grain derived from portal_ellipse.gdshader (no spin animation).
vec3 apply_portal_finish(vec3 col, vec2 pattern_uv, vec3 accent, float px_scale, float strength) {
	float dist = length(pattern_uv * 0.12);
	float angle = atan(pattern_uv.y, pattern_uv.x);
	float spiral_phase = angle + dist * 5.5;
	vec2 spin_dir = vec2(cos(spiral_phase), sin(spiral_phase));
	vec2 spiral_cell = floor(spin_dir * dist * px_scale * 1.15);
	float grain = cell_hash(spiral_cell);
	float ring = fract(dist * 6.0);
	col = mix(col, accent, step(0.82, grain) * strength * 0.42);
	col = mix(col, accent * 0.55 + col * 0.45, ring * strength * 0.2);
	return col;
}
