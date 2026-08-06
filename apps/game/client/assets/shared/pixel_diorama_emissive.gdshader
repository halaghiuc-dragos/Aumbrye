shader_type spatial;
render_mode unshaded, specular_disabled;

#include "res://assets/shared/pixel_diorama_finish.gdshaderinc"

// Quantized glow surface for torches, crystals, runes, and portal trim. Keeps
// emissive props inside the same palette banding as shaded pixel surfaces.

uniform vec4 color_core : source_color = vec4(1.0, 0.62, 0.28, 1.0);
uniform vec4 color_edge : source_color = vec4(0.85, 0.34, 0.12, 1.0);
uniform float pixel_scale : hint_range(1.0, 64.0) = 8.0;
uniform float color_levels : hint_range(2.0, 16.0) = 6.0;
uniform float emission_energy : hint_range(0.0, 8.0) = 1.6;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.35;
uniform float pulse_speed : hint_range(0.0, 8.0) = 0.0;
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.18;
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 flash_color : source_color = vec3(1.0);
uniform float flash_emission : hint_range(0.0, 4.0) = 0.0;
uniform float dissolve_clip : hint_range(0.0, 1.0) = 1.0;
uniform vec3 dissolve_origin = vec3(0.0);
uniform vec3 dissolve_dir = vec3(0.0, 1.0, 0.0);
uniform float dissolve_sweep : hint_range(0.0, 1.0) = 0.6;

varying vec3 v_local_pos;
varying vec3 v_local_normal;

void vertex() {
	v_local_pos = VERTEX;
	v_local_normal = NORMAL;
}

void fragment() {
	vec2 uv = triplanar_pattern_uv(v_local_pos, v_local_normal, pixel_scale);
	vec2 cell = floor(uv);
	float grain = cell_hash(cell);

	vec3 col = mix(color_edge.rgb, color_core.rgb, step(0.35, grain));
	col = mix(col, color_core.rgb * 1.15, step(0.86, grain) * grain_strength);

	float pulse = 1.0;
	if (pulse_speed > 0.001) {
		// Stepped pulse so flicker reads as frames rather than a smooth fade.
		float phase = floor(fract(TIME * pulse_speed) * 4.0) / 4.0;
		pulse = 1.0 + (phase - 0.5) * pulse_amount * 2.0;
	}

	if (dissolve_clip < 0.999) {
		// Keep discard block in sync with pixel_diorama_surface.gdshader.
		vec3 cell3 = floor(v_local_pos * pixel_scale * 0.5);
		float dither = cell_hash(cell3.xz + vec2(cell3.y * 17.0, cell3.y * 31.0));
		vec3 sweep_dir = dissolve_dir;
		if (length(sweep_dir) < 0.001) {
			sweep_dir = vec3(0.0, 1.0, 0.0);
		} else {
			sweep_dir = normalize(sweep_dir);
		}
		float sweep = clamp(dot(normalize(v_local_pos - dissolve_origin), sweep_dir), -1.0, 1.0);
		float threshold = dissolve_clip - dissolve_sweep * (0.5 - sweep * 0.5);
		if (dither > threshold) {
			discard;
		}
	}

	vec3 quantized = quantize_color(col, color_levels);
	quantized = mix(quantized, flash_color, flash_amount);
	ALBEDO = quantized;
	EMISSION = quantized * emission_energy * pulse + flash_color * flash_amount * flash_emission;
}
