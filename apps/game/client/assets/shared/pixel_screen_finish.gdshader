shader_type canvas_item;

// Screen-space finish applied to the low-res SubViewportContainer, before the
// nearest-neighbour upscale. Everything here works per source pixel so the
// output stays crisp; no blur, bloom, or sub-pixel sampling is allowed.

uniform float contrast : hint_range(0.5, 2.0) = 1.08;
uniform float saturation : hint_range(0.0, 2.0) = 1.06;
uniform float lift : hint_range(-0.2, 0.2) = 0.0;
uniform vec4 shadow_tint : source_color = vec4(0.18, 0.16, 0.26, 1.0);
uniform float shadow_tint_amount : hint_range(0.0, 1.0) = 0.14;
uniform vec4 highlight_tint : source_color = vec4(1.0, 0.94, 0.82, 1.0);
uniform float highlight_tint_amount : hint_range(0.0, 1.0) = 0.1;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.18;
uniform float vignette_softness : hint_range(0.1, 2.0) = 0.85;
uniform float posterize_levels : hint_range(0.0, 64.0) = 0.0;

float luminance(vec3 color) {
	return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec3 col = source.rgb;

	col = (col - 0.5) * contrast + 0.5 + lift;

	float luma = luminance(col);
	col = mix(vec3(luma), col, saturation);

	// Split tone: cool the shadows, warm the highlights. Cheap way to give the
	// palette depth without adding light sources.
	col = mix(col, shadow_tint.rgb * col * 2.0, (1.0 - luma) * shadow_tint_amount);
	col = mix(col, highlight_tint.rgb * col, luma * highlight_tint_amount);

	if (vignette_strength > 0.001) {
		vec2 centered = UV - vec2(0.5);
		float falloff = smoothstep(vignette_softness, 0.2, length(centered));
		col *= mix(1.0 - vignette_strength, 1.0, falloff);
	}

	if (posterize_levels >= 2.0) {
		col = floor(col * posterize_levels + 0.5) / posterize_levels;
	}

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), source.a);
}
