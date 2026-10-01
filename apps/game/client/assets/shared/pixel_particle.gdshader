shader_type spatial;
render_mode unshaded, specular_disabled;

#include "res://assets/shared/pixel_diorama_finish.gdshaderinc"

// Burst particles (sparks, shards, flakes). The colour comes from the particle itself
// (`COLOR`, i.e. the emitter's colour), so one material serves every tint and the pool never needs
// a material per colour. Same banding and two-tone grain as the emissive surface shader.

uniform float pixel_scale : hint_range(1.0, 64.0) = 8.0;
uniform float color_levels : hint_range(2.0, 16.0) = 6.0;
uniform float emission_energy : hint_range(0.0, 8.0) = 1.0;

varying vec3 v_local_pos;
varying vec3 v_local_normal;

void vertex() {
	v_local_pos = VERTEX;
	v_local_normal = NORMAL;
}

void fragment() {
	vec2 uv = triplanar_pattern_uv(v_local_pos, v_local_normal, pixel_scale);
	float grain = cell_hash(floor(uv));
	vec3 base = COLOR.rgb;
	vec3 col = mix(base * 0.75, base, step(0.35, grain));
	vec3 quantized = quantize_color(col, color_levels);
	ALBEDO = quantized;
	EMISSION = quantized * emission_energy;
}
