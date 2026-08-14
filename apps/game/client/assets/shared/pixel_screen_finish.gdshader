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
uniform float damage_pulse : hint_range(0.0, 1.0) = 0.0;
uniform vec4 pulse_tint : source_color = vec4(0.62, 0.08, 0.08, 1.0);

// Sustained low-health tension. Deliberately not the same channel as damage_pulse: that one is a
// one-shot flash that decays to nothing, so while it is fading it cannot also hold a state. A
// player at 20% health needs the frame to *stay* wrong, and still needs each individual hit to
// register on top of it.
//
// It breathes rather than sitting still, because a constant tint stops being visible after a few
// seconds — the eye adapts to it and it just becomes the game's colour. Movement does not adapt
// away. The breath is quantized to a handful of steps for the same reason the rest of the pipeline
// bands its shading: a smooth pulse at this resolution reads as a fault, not as an effect.
uniform float distress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 distress_tint : source_color = vec4(0.46, 0.05, 0.07, 1.0);
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

	// Applied before the damage pulse so a fresh hit still flashes brighter than the standing
	// tension, keeping "I just took damage" distinguishable from "I am nearly dead".
	if (distress > 0.001) {
		vec2 centered = UV - vec2(0.5);
		float edge = smoothstep(0.10, 0.66, length(centered));
		float breath = 0.70 + 0.30 * sin(TIME * 2.3);
		breath = floor(breath * 5.0 + 0.5) / 5.0;
		float amount = distress * edge * breath;
		col = mix(col, distress_tint.rgb * col * 1.15, amount);
		// Pull the corners down as well. Tint alone reads as a colour grade; darkening the frame
		// is what makes the play space feel like it is closing in.
		col *= mix(1.0, 0.78, amount);
	}

	if (damage_pulse > 0.001) {
		vec2 centered = UV - vec2(0.5);
		float edge = smoothstep(0.15, 0.55, length(centered));
		col = mix(col, pulse_tint.rgb * col * 1.35, damage_pulse * edge);
	}

	if (posterize_levels >= 2.0) {
		col = floor(col * posterize_levels + 0.5) / posterize_levels;
	}

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), source.a);
}
